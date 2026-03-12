---
name: github-cli-publisher
description: Install and configure GitHub CLI, Git Credential Manager, and GitHub publishing workflows on Windows. Use this skill whenever the user asks to install `gh`, log into GitHub from the terminal, configure GitHub authentication, publish a local folder or skill repo to GitHub, create a clean publish repo from a subdirectory, set `origin`, push `main`, create a release, or upload assets such as `.skill` files. Also use it for requests like "帮我上传到 GitHub", "安装 GitHub CLI", "配置 gh", "连上 GitHub", or "帮我发 release".
compatibility: Windows PowerShell, git, network access, browser or token-based GitHub authentication.
metadata:
  author: Codex
  version: "0.1.0"
---

# GitHub CLI Publisher

Use this skill to automate the full Windows GitHub publishing path: install `gh`, authenticate safely, prepare a clean repository, push code, and publish releases.

This skill is based on a real workflow that successfully handled:

- `winget` install failure for `GitHub.cli`
- fallback to the official GitHub CLI MSI installer
- `gh auth login` instability
- Git Credential Manager browser login as a more reliable Git auth path
- publishing a subdirectory without contaminating an unrelated parent repository
- `git push` network instability
- fallback to GitHub API for repository metadata, README updates, releases, and asset uploads

Read [references/windows-publish-flow.md](references/windows-publish-flow.md) when you need the detailed decision tree.

Use [scripts/check-github-setup.ps1](scripts/check-github-setup.ps1) to inspect the current machine state.
Use [scripts/install-gh-windows.ps1](scripts/install-gh-windows.ps1) to install GitHub CLI on Windows when `gh` is missing.
Use [scripts/init-clean-publish-repo.ps1](scripts/init-clean-publish-repo.ps1) to turn a nested subdirectory into a standalone publish repository without touching the parent repo.

On Windows systems with restrictive execution policy, invoke bundled scripts like this:

`powershell -NoProfile -ExecutionPolicy Bypass -File <script-path>`

## When to use this skill

Apply it when the user wants to:

- install GitHub CLI
- log into GitHub from a Windows terminal
- configure Git and Git Credential Manager for GitHub
- upload a local project or skill to GitHub
- create a GitHub repository from a folder
- set or repair `origin`
- push a branch such as `main`
- create a GitHub release
- upload packaged artifacts such as `.skill`, `.zip`, or installer files

## Safety boundaries

- Do not create, overwrite, or delete remote repositories unless the user clearly intends GitHub publishing.
- Do not expose tokens, passwords, or raw credential-manager output.
- If authentication requires browser approval or a personal access token, keep the user informed and stop at that checkpoint.
- If the current folder is part of an unrelated Git repository, prefer creating a dedicated publish repository in a sibling directory rather than mutating the unrelated repo.

## Core workflow

1. Inspect the current environment before changing anything.
2. Detect whether `gh`, `git`, and Git Credential Manager are installed and usable.
3. Install `gh` if needed.
4. Establish GitHub authentication through the most reliable available path.
5. Decide whether to publish the current repo or build a clean publish repo from a subdirectory.
6. Configure or create the remote repository.
7. Push the branch.
8. Create or update release metadata and upload assets if requested.
9. Report the final repository URL and any remaining manual steps.

## Environment inspection

Start with:

- `scripts/check-github-setup.ps1`
- `git status --short --branch`
- `git remote -v`
- `gh auth status` if `gh` is present

Focus on the actual publish path, not just tool presence:

- Is `gh` installed?
- Is GitHub authentication already available through `gh` or Git Credential Manager?
- Is the current directory already the right repository to publish?
- Is there an `origin` remote already, and is it the correct one?

## Installation strategy

On Windows, prefer this order:

1. If `gh` already exists, verify the version and skip installation.
2. Try the official `winget` package `GitHub.cli`.
3. If `winget` cannot find an applicable installer or fails, download the latest official MSI from the `cli/cli` GitHub releases page and install it silently.
4. Verify the installed path and version after installation.

The bundled installer script follows this approach.

## Authentication strategy

Prefer the most reliable path for the job:

1. If `git push` is the main goal, Git Credential Manager authentication is often sufficient even if `gh auth login` is flaky.
2. Use `git credential-manager github login --browser --url https://github.com` as the preferred Git auth path on Windows.
3. Use `gh auth login` when the user specifically wants GitHub CLI authenticated for `gh repo` or `gh release` commands.
4. If browser auth is unstable but Git Credential Manager already has a usable GitHub account, reuse that state instead of reauthenticating.

## Repository preparation

Before publishing, decide whether the current directory should be pushed directly.

Publish the current directory when:

- it is already the intended standalone repository
- its `origin` remote is correct or intentionally empty

Create a clean publish repository when:

- the current directory is nested inside an unrelated parent repository
- the parent repo has unrelated dirty state
- the user only wants a subfolder published

When building a clean publish repository:

- create a dedicated sibling directory
- copy only the intended publish files
- initialize a fresh Git repository there
- set the local branch to `main`
- make a clean initial commit

If the task is straightforward on Windows, prefer using the bundled `init-clean-publish-repo.ps1` script instead of reimplementing the copy/init flow by hand.

## Push and remote rules

- Use HTTPS by default unless the user requests SSH.
- Set or replace `origin` only when the destination repository is clearly identified.
- Push `main` with upstream tracking.
- If Git connectivity is flaky, try the Windows SSL backend `schannel`.

## GitHub API fallback

If direct `git push` or `gh` release operations are unstable but GitHub authentication is already available through Git Credential Manager:

- do not print the token
- reuse the existing credential only for the GitHub actions the user requested
- use the GitHub API to:
  - create the repository
  - update repository description or topics
  - update files such as `README.md`
  - create releases
  - upload release assets

Use this fallback only after the user has clearly requested publishing work.

## Output expectations

When the task completes, report:

1. what was installed or configured
2. the repository path used for publishing
3. the repository URL
4. the release URL if a release was created
5. any manual step still required, such as browser login

## Example trigger requests

- "Install GitHub CLI and get this Windows machine ready to publish repos."
- "Help me upload this folder to GitHub."
- "This subfolder is inside another repo. Publish only this part."
- "Set up `gh`, connect Git to GitHub, and push `main`."
- "Create a GitHub release and upload these `.skill` files."
- "帮我安装 GitHub CLI 并登录。"
- "帮我把这个 skill 仓库传到 GitHub。"
- "这个目录嵌在别的仓库里，单独发到 GitHub。"
