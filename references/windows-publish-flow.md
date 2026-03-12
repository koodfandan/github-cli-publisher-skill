# Windows Publish Flow

This note captures the decision tree behind the skill.

## 1. Inspect first

Check:

- `gh` path and version
- `git` version
- Git Credential Manager availability
- `gh auth status`
- `git credential-manager github list`
- current repo state
- remotes

## 2. Install GitHub CLI

Preferred order:

1. Existing install
2. `winget install --id GitHub.cli`
3. Official MSI from `https://github.com/cli/cli/releases/latest`

Verify:

- resolved `gh.exe` path
- `gh --version`

## 3. Authenticate

Preferred order on Windows:

1. `git credential-manager github login --browser --url https://github.com`
2. `gh auth login`
3. token-based fallback if the user explicitly provides one

Why Git Credential Manager first:

- it is closer to the `git push` path
- it can succeed even when `gh auth login` is unreliable

## 4. Prepare the correct repository

Use the current repo only if it is actually the intended publish unit.

If the target folder is nested inside another project:

- create a new clean publish repo
- copy only the target files
- initialize Git there
- commit once

## 5. Push strategy

Try:

- normal HTTPS push
- `http.sslBackend=schannel` if Git networking is unstable

If GitHub access is browser-OK but `git push` remains unstable, the workflow may still succeed through GitHub API calls for metadata and releases.

## 6. Release strategy

Preferred order:

1. `gh release create`
2. GitHub API fallback with existing auth

Typical assets:

- `.skill`
- `.zip`
- installers

## 7. Final report

Return:

- install status
- auth status
- publish repo path
- remote URL
- repo URL
- release URL
- any unfinished manual step
