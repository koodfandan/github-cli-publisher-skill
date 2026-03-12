# github-cli-publisher

A Codex skill for Windows GitHub publishing workflows.

This skill helps automate:

- installing GitHub CLI
- checking Git, GitHub CLI, and Git Credential Manager state
- authenticating GitHub access on Windows
- preparing a clean publish repository from a nested subdirectory
- configuring `origin` and pushing `main`
- creating releases and uploading packaged assets
- falling back to GitHub API when direct `git push` or `gh` flows are unreliable

## Included files

- `SKILL.md`
- `references/windows-publish-flow.md`
- `scripts/check-github-setup.ps1`
- `scripts/install-gh-windows.ps1`
- `scripts/init-clean-publish-repo.ps1`
- `evals/evals.json`

## Package

The packaged artifact is available at:

- `packages/github-cli-publisher.skill`

## Test summary

Validated locally on Windows with these checks:

- environment detection script reports installed `gh`, `git`, and Git Credential Manager state
- install script correctly detects an existing `gh` installation
- clean publish repo helper creates a standalone `main` branch repository
- the helper excludes `node_modules`
- the helper adds the destination to `safe.directory` so follow-up Git commands succeed

## Source

This skill was derived from a real publishing workflow executed on Windows PowerShell with GitHub CLI and Git Credential Manager.
