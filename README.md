# github-cli-publisher

A Codex skill for automating Windows GitHub publishing workflows.

This repository contains the skill source plus a packaged `.skill` artifact.

## What it automates

- detect `gh`, `git`, and Git Credential Manager state
- install GitHub CLI with MSI fallback when `winget` is not enough
- reuse Git Credential Manager auth when `gh auth login` is missing or flaky
- turn a nested subfolder into a clean standalone publish repository
- create or update the GitHub repository
- set `origin` and push the publish branch
- create a release and upload packaged assets
- show a JSON publish plan before touching GitHub

## Included files

- `SKILL.md`
- `references/windows-publish-flow.md`
- `scripts/check-github-setup.ps1`
- `scripts/install-gh-windows.ps1`
- `scripts/init-clean-publish-repo.ps1`
- `scripts/publish-github-repo.ps1`
- `evals/evals.json`
- `packages/github-cli-publisher.skill`

## Validation

The current version was validated with:

- PowerShell parser checks for all bundled scripts
- JSON validation for `evals/evals.json`
- `-PlanOnly` output from `scripts/publish-github-repo.ps1`
- a local end-to-end smoke test that published a nested folder to a local bare Git remote

## Main entrypoint

For the full workflow, use:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-github-repo.ps1 `
  -SourceDir <folder> `
  -RepoOwner <owner> `
  -RepoName <repo> `
  -Visibility public
```
