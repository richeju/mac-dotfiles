# Repository delivery rules

- Make changes on a topic branch and publish them through a pull request.
- Never push directly to `main`, force-push `main`, use `gh pr merge --admin`,
  or weaken repository protections to deliver a change.
- When the user authorizes delivery, enable squash auto-merge on that PR and
  wait for the required `secret-scan`, `shell-tests`, and `macos-validation`
  checks. Report blockers instead of bypassing checks or unresolved reviews.
- Run relevant tests before publishing. Keep GitHub Actions pinned to full
  commit SHAs and verify those SHAs against upstream releases when updating.
- Keep existing user changes intact. Do not apply dotfiles or run machine
  maintenance merely to test repository changes; use isolated fixtures.
