# Windows Publish Flow

Use this reference when you need a compact decision tree for Windows GitHub publishing tasks.

Preferred path:

1. Run `scripts/check-github-setup.ps1` to inspect `gh`, `git`, Git Credential Manager, and current auth state.
2. If `gh` is missing, run `scripts/install-gh-windows.ps1`.
3. If the user wants the whole publish flow handled, prefer `scripts/publish-github-repo.ps1` over hand-built command sequences.

Inside the publish flow:

1. Reuse existing GitHub auth if `gh auth status` already works.
2. If CLI auth is missing but Git pushes are the immediate goal, Git Credential Manager browser login is still the most reliable Windows path.
3. If the source folder is nested inside an unrelated repo, create a clean sibling publish repo first.
4. Set or repair `origin`, then push with HTTPS. Retry with the Windows SSL backend when the first push fails.
5. If remote creation, release creation, or asset upload are requested, use GitHub API calls when higher-level `gh` commands are unreliable.

Bundled scripts:

- `scripts/check-github-setup.ps1`: machine-state inspection
- `scripts/install-gh-windows.ps1`: GitHub CLI installer with MSI fallback
- `scripts/init-clean-publish-repo.ps1`: build a standalone publish repo from a nested folder
- `scripts/publish-github-repo.ps1`: end-to-end orchestration for repo creation, remote setup, push, and release upload
