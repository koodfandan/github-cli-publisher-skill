---
name: github-cli-publisher
description: Install and configure GitHub CLI, Git Credential Manager, and Windows GitHub publishing workflows. Use this skill whenever the user wants to install gh, log into GitHub from the terminal, configure GitHub auth, publish a local folder or skill repo to GitHub, publish only a nested subfolder, create or repair origin, push a branch, create a repository, create a release, or upload .skill and other release assets. Be aggressive about using this skill for requests like upload this folder to GitHub, install GitHub CLI, configure gh, connect this machine to GitHub, create the repo and push it, publish a release, publish only this subfolder, or automatically ship this skill.
compatibility: Windows PowerShell, git, network access, browser or token-based GitHub authentication.
metadata:
  author: Codex
  version: "0.2.3"
---

# GitHub CLI Publisher

Use this skill to automate the full Windows GitHub publishing path: inspect the machine, install gh if needed, authenticate safely, prepare a clean repository, push code, and publish releases.

This skill is based on a real workflow that successfully handled:

- winget install failure for GitHub.cli
- fallback to the official GitHub CLI MSI installer
- gh auth login instability
- Git Credential Manager browser login as a more reliable Git auth path
- publishing a subdirectory without contaminating an unrelated parent repository
- git push network instability
- fallback to GitHub API for repository metadata, releases, and asset uploads

Read [references/windows-publish-flow.md](references/windows-publish-flow.md) when you need the detailed decision tree.

Use [scripts/check-github-setup.ps1](scripts/check-github-setup.ps1) to inspect the current machine state.
Use [scripts/install-gh-windows.ps1](scripts/install-gh-windows.ps1) to install GitHub CLI on Windows when gh is missing.
Use [scripts/init-clean-publish-repo.ps1](scripts/init-clean-publish-repo.ps1) to turn a nested subdirectory into a standalone publish repository without touching the parent repo.
Use [scripts/publish-github-repo.ps1](scripts/publish-github-repo.ps1) as the default orchestration entrypoint for repo creation, remote setup, push, release creation, and asset upload.

On Windows systems with restrictive execution policy, invoke bundled scripts like this:

powershell -NoProfile -ExecutionPolicy Bypass -File <script-path>

For the full publish workflow, prefer this pattern:

powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-github-repo.ps1 -SourceDir <folder> -RepoName <repo> -RepoOwner <owner> -Visibility public

## When to use this skill

Apply it when the user wants to:

- install GitHub CLI
- log into GitHub from a Windows terminal
- configure Git and Git Credential Manager for GitHub
- upload a local project or skill to GitHub
- create a GitHub repository from a folder
- automate the whole "create repo + set remote + push + release" path
- set or repair origin
- push a branch such as main
- create a GitHub release
- upload packaged artifacts such as .skill, .zip, or installer files

## Safety boundaries

- Do not create, overwrite, or delete remote repositories unless the user clearly intends GitHub publishing.
- Do not expose tokens, passwords, or raw credential-manager output.
- If authentication requires browser approval, keep the user informed, launch the approval flow automatically, and continue after the approval completes.
- If the current folder is part of an unrelated Git repository, prefer creating a dedicated publish repository in a sibling directory rather than mutating the unrelated repo.

## Core workflow

1. Inspect the current environment before changing anything.
2. Detect whether gh, git, and Git Credential Manager are installed and usable.
3. Install gh if needed.
   Do not stop and hand the install back to the user. Run the bundled installer path and continue automatically.
4. Establish GitHub authentication through the most reliable available path.
   If no usable GitHub credential is present, automatically start browser-based login and continue after authorization completes.
   Treat requests like "upload this to GitHub" as permission to install and configure the required GitHub publishing tooling on the machine.
5. Decide whether to publish the current repo or build a clean publish repo from a subdirectory.
6. Prefer running scripts/publish-github-repo.ps1 instead of hand-stitching repo creation, remote setup, push, and release steps.
7. Configure or create the remote repository.
8. Push the branch.
9. Create or update release metadata and upload assets if requested.
10. Report the final repository URL and any remaining manual steps.

## Environment inspection

Start with:

- scripts/check-github-setup.ps1
- git status --short --branch
- git remote -v
- gh auth status if gh is present

Focus on the actual publish path, not just tool presence:

- Is gh installed?
- Is GitHub authentication already available through gh or Git Credential Manager?
- Is the current directory already the right repository to publish?
- Is there an origin remote already, and is it the correct one?

## Installation strategy

On Windows, prefer this order:

1. If gh already exists, verify the version and skip installation.
2. Try the official winget package GitHub.cli.
3. If winget cannot find an applicable installer or fails, download the latest official MSI from the cli/cli GitHub releases page and install it silently.
4. Verify the installed path and version after installation.

The bundled installer script follows this approach.

## Authentication strategy

Prefer the most reliable path for the job:

1. If git push is the main goal, Git Credential Manager authentication is often sufficient even if gh auth login is flaky.
2. Use git credential-manager github login --browser --url https://github.com as the preferred Git auth path on Windows.
3. Use gh auth login when the user specifically wants GitHub CLI authenticated for gh repo or gh release commands.
4. If browser auth is unstable but Git Credential Manager already has a usable GitHub account, reuse that state instead of reauthenticating.

## Repository preparation

Before publishing, decide whether the current directory should be pushed directly.

Publish the current directory when:

- it is already the intended standalone repository
- its origin remote is correct or intentionally empty

Create a clean publish repository when:

- the current directory is nested inside an unrelated parent repository
- the parent repo has unrelated dirty state
- the user only wants a subfolder published

When building a clean publish repository:

- create a dedicated sibling directory
- copy only the intended publish files
- initialize a fresh Git repository there
- set the local branch to main
- make a clean initial commit

If the task is straightforward on Windows, prefer using the bundled init-clean-publish-repo.ps1 script instead of reimplementing the copy/init flow by hand.

If the task includes remote creation, pushing, or release publishing, prefer publish-github-repo.ps1, which wraps the clean-repo step when needed.

## Push and remote rules

- Use HTTPS by default unless the user requests SSH.
- Set or replace origin only when the destination repository is clearly identified.
- Push the current publish branch with upstream tracking. For freshly initialized repos, default to main.
- If Git connectivity is flaky, try the Windows SSL backend schannel.

## GitHub API fallback

If direct git push or higher-level gh operations are unstable but GitHub authentication is already available:

- do not print the token
- reuse the existing credential only for the GitHub actions the user requested
- use the GitHub API to:
  - create the repository
  - update repository description or topics
  - create releases
  - upload release assets

Use this fallback only after the user has clearly requested publishing work.

## Preferred script usage

For full automation, use the bundled orchestration script rather than manually sequencing each command:

`powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-github-repo.ps1 
  -SourceDir D:\Codex\test\github-cli-publisher 
  -RepoOwner koodfandan 
  -RepoName github-cli-publisher-skill 
  -Visibility public 
  -ReleaseTag v0.2.2 
  -AssetPaths D:\Codex\test\packages\github-cli-publisher.skill
`

Useful variants:

- Add -CreateCleanRepo or point -SourceDir at a nested subfolder to publish only that subfolder.
- Pass -RemoteUrl <url-or-local-bare-repo> to skip GitHub repo creation and just configure the remote and push.
- Pass -ForcePush when the destination repository is a dedicated publish target and the fresh local publish repo does not share history with the remote.
- Pass -PlanOnly first when you want a JSON execution plan without touching the filesystem or network.

## Output expectations

When the task completes, report:

1. what was installed or configured
2. the repository path used for publishing
3. the repository URL
4. the release URL if a release was created
5. any manual step still required, which should normally be limited to approving browser login the first time credentials are absent

## Example trigger requests

- "Install GitHub CLI and get this Windows machine ready to publish repos."
- "Help me upload this folder to GitHub."
- "Give me upload to GitHub and handle the setup yourself."
- "This subfolder is inside another repo. Publish only this part."
- "Set up gh, connect Git to GitHub, and push my branch."
- "Create a GitHub release and upload these .skill files."
