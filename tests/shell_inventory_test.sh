#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/shell_sources.sh
source "$REPO_ROOT/tests/lib/shell_sources.sh"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mac-dotfiles-sources-test.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
# macOS TMPDIR can end in / or use a symlink; compare canonical fixture paths.
WORK_DIR="$(cd "$WORK_DIR" && pwd -P)"
FIXTURE="$WORK_DIR/repo with spaces"
mkdir -p "$FIXTURE/nested name" "$FIXTURE/skills" "$WORK_DIR/bin" "$WORK_DIR/not-a-repo"
git -C "$FIXTURE" init -q

fail() {
    echo "[FAIL] $1" >&2
    exit 1
}

assert_path_count() {
    local manifest="$1" expected="$2" wanted="$3" path count=0
    while IFS= read -r -d '' path; do
        if [[ "$path" == "$expected" ]]; then
            count=$((count + 1))
        fi
    done <"$manifest"
    [[ "$count" -eq "$wanted" ]] || fail "Unexpected inventory count for: $expected"
}

printf '/ignored.sh\n' >"$FIXTURE/.gitignore"
for path in 'tracked file.sh' 'deleted.sh' 'skills/helper.sh' 'notes.md'; do
    printf '#!/usr/bin/env bash\ntrue\n' >"$FIXTURE/$path"
done
git -C "$FIXTURE" add .
rm "$FIXTURE/deleted.sh"
for path in $'line\nbreak.sh' 'back\slash.sh' '.hidden.sh' 'ignored.sh'; do
    printf '#!/usr/bin/env bash\ntrue\n' >"$FIXTURE/$path"
done
cat >"$FIXTURE/nested name/rendered.sh.tmpl" <<'TEMPLATE'
#!/usr/bin/env bash
{{- $value := "example" -}}
printf '%s\n' '{{ .message }}'
TEMPLATE
list_repository_files "$FIXTURE" >"$WORK_DIR/files"
list_shell_sources "$FIXTURE" >"$WORK_DIR/scripts"
for path in 'tracked file.sh' 'skills/helper.sh' $'line\nbreak.sh' 'back\slash.sh' '.hidden.sh' 'nested name/rendered.sh.tmpl'; do
    assert_path_count "$WORK_DIR/files" "$path" 1
    assert_path_count "$WORK_DIR/scripts" "$path" 1
done
for path in deleted.sh ignored.sh; do
    assert_path_count "$WORK_DIR/files" "$path" 0
    assert_path_count "$WORK_DIR/scripts" "$path" 0
done
assert_path_count "$WORK_DIR/files" notes.md 1
assert_path_count "$WORK_DIR/scripts" notes.md 0

prepare_shell_source "$FIXTURE/tracked file.sh" >"$WORK_DIR/prepared"
cmp -s "$WORK_DIR/prepared" "$FIXTURE/tracked file.sh" || fail "Plain shell source changed"
prepare_shell_source "$FIXTURE/nested name/rendered.sh.tmpl" >"$WORK_DIR/prepared"
cat >"$WORK_DIR/expected" <<'EXPECTED'
#!/usr/bin/env bash
printf '%s\n' 'template_value'
EXPECTED
cmp -s "$WORK_DIR/prepared" "$WORK_DIR/expected" || fail "Template preparation changed"
bash -n "$WORK_DIR/prepared"

status=0
list_shell_sources "$WORK_DIR/not-a-repo" >/dev/null 2>&1 || status=$?
[[ "$status" -ne 0 ]] || fail "Git lookup errors must not silently pass"

# Exercise the actual lint driver with stub tools, not an alternative file walker.
mkdir -p "$FIXTURE/tests/lib"
cp "$REPO_ROOT/tests/shell_quality.sh" "$FIXTURE/tests/shell_quality.sh"
cp "$REPO_ROOT/tests/lib/shell_sources.sh" "$FIXTURE/tests/lib/shell_sources.sh"
cat >"$WORK_DIR/bin/shellcheck" <<'CHECKER'
#!/usr/bin/env bash
set -euo pipefail
candidate=""
for arg in "$@"; do
    candidate="$arg"
done
[[ -f "$candidate" ]] || exit 30
printf '%s\0' "$candidate" >>"$QUALITY_CALLS"
case "$candidate" in
    "$QUALITY_REPO"/*) ;;
    *) ! grep -q '{{' "$candidate" || exit 31 ;;
esac
[[ "${QUALITY_FAIL:-0}" -eq 0 ]] || exit 19
CHECKER
chmod +x "$WORK_DIR/bin/shellcheck"
cp "$WORK_DIR/bin/shellcheck" "$WORK_DIR/bin/shfmt"

run_quality() {
    PATH="$WORK_DIR/bin:$PATH" QUALITY_CALLS="$WORK_DIR/quality-calls" \
        QUALITY_REPO="$FIXTURE" QUALITY_FAIL="${QUALITY_FAIL:-0}" \
        bash "$FIXTURE/tests/shell_quality.sh" "$@"
}

: >"$WORK_DIR/quality-calls"
run_quality all >"$WORK_DIR/quality-output" || {
    status=$?
    cat "$WORK_DIR/quality-output" >&2
    fail "Quality driver exited with status $status"
}
for path in 'tracked file.sh' $'line\nbreak.sh' 'back\slash.sh' '.hidden.sh'; do
    assert_path_count "$WORK_DIR/quality-calls" "$FIXTURE/$path" 2
done
assert_path_count "$WORK_DIR/quality-calls" "$FIXTURE/skills/helper.sh" 0
assert_path_count "$WORK_DIR/quality-calls" "$FIXTURE/ignored.sh" 0
assert_path_count "$WORK_DIR/quality-calls" "$FIXTURE/deleted.sh" 0

template_checks=0
while IFS= read -r -d '' path; do
    case "$path" in
        */nested\ name/rendered.sh) template_checks=$((template_checks + 1)) ;;
    esac
done <"$WORK_DIR/quality-calls"
[[ "$template_checks" -eq 2 ]] || fail "Prepared templates must reach both quality tools"

status=0
QUALITY_FAIL=1 run_quality shellcheck >"$WORK_DIR/quality-output" 2>&1 || status=$?
[[ "$status" -eq 19 ]] || fail "Lint failure must propagate"
if grep -q '\[PASS\]' "$WORK_DIR/quality-output"; then
    fail "Failed lint must not print a success message"
fi
status=0
run_quality unknown >/dev/null 2>&1 || status=$?
[[ "$status" -eq 2 ]] || fail "Invalid quality mode must return 2"

echo "[PASS] shell source inventory, template preparation and quality driver"
