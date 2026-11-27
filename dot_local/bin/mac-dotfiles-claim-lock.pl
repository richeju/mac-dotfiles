use strict;
use warnings;
use Fcntl qw(:flock);

# Serialize only inspection and publication. The PID directory remains the
# operation lock understood by existing clients; the guard inode stays in place.
my ($lock, $claimant) = @ARGV;
my $pid_file = "$lock/pid";
umask 0077;

sub fail {
    warn "$_[0]: $!\n";
    exit 2;
}

sub busy {
    warn "Another mac-dotfiles operation owns or is initializing $lock\n";
    exit 1;
}

# If a PID was reused (for example after a reboot), its process started later
# than the PID file. Preserve the lock if ps cannot establish this reliably.
sub pid_is_reused {
    my ($pid, $lock_age) = @_;
    return 0 if $lock_age < 3;
    open my $ps, '-|', '/bin/ps', '-p', $pid, '-o', 'etime=' or return 0;
    my $elapsed = <$ps> // '';
    close $ps or return 0;
    return 0 unless $elapsed =~ /^\s*(?:(\d+)-)?(?:(\d+):)?(\d+):(\d+)\s*$/;
    my $seconds = ($1 // 0) * 86400 + ($2 // 0) * 3600 + $3 * 60 + $4;
    return $lock_age > $seconds + 2;
}

open my $guard, '>>', "$lock.guard" or fail("Cannot open $lock.guard");
flock($guard, LOCK_EX) or fail("Cannot guard $lock");
unless (mkdir $lock, 0700) {
    $!{EEXIST} or fail("Cannot create $lock");
    # An existing owner may be releasing its directory at this instant.
    busy() unless -e $lock || -l $lock;
    -d $lock && !-l $lock or fail("Invalid lock directory $lock");

    my $owner = '';
    my $mtime = (stat $lock)[9];
    if (-e $pid_file || -l $pid_file) {
        -f $pid_file && !-l $pid_file or fail("Invalid PID file $pid_file");
        open my $existing, '<', $pid_file or do {
            busy() if $!{ENOENT};
            fail("Cannot read $pid_file");
        };
        $owner = <$existing> // '';
        chomp $owner;
        $mtime = (stat $existing)[9];
    }
    busy() unless defined $mtime;
    my $age = time - $mtime;
    if ($owner =~ /^[1-9][0-9]{0,9}$/ && $owner <= 2147483647) {
        if (kill(0, $owner) || $!{EPERM}) {
            busy() unless pid_is_reused($owner, $age);
        }
    } else {
        # Older tools publish their PID just after mkdir. Give a freshly
        # created directory time to acquire its owner before adopting it.
        busy() if $age < 60;
    }
    warn "Recovering abandoned mac-dotfiles lock: $lock\n";
}

open my $pid, '>', $pid_file or fail("Cannot publish $pid_file");
print {$pid} "$claimant\n" or fail("Cannot write $pid_file");
close $pid or fail("Cannot close $pid_file");
