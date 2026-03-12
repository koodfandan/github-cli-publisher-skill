# github-cli-publisher

A Codex skill for automating Windows GitHub publishing workflows.

## What changed in v0.2.3

- aligned the skill behavior with the intended default: if the user says to upload to GitHub, the skill installs `gh` if needed and continues automatically
- added automatic browser-based authentication kickoff when no usable GitHub credential is present
- clarified that the browser approval step is launched automatically and the publish flow continues after approval
- kept the validated publish chain intact: create repo, configure remote, push, create release, and upload `.skill` assets

## Validation summary

This version was validated with:

- PowerShell parser check for `scripts/publish-github-repo.ps1`
- `-PlanOnly` execution for the full publish entrypoint
- a real GitHub production-path test that created a temporary private repository, pushed `main`, created a release, and uploaded `github-cli-publisher.skill`
