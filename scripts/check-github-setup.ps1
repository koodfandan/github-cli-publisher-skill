$ErrorActionPreference = 'SilentlyContinue'

function Get-ExecutablePath {
  param(
    [string[]]$Candidates,
    [string]$CommandName
  )

  foreach ($path in $Candidates) {
    if ($path -and (Test-Path $path)) {
      return $path
    }
  }

  if ($CommandName) {
    $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($cmd) {
      return $cmd.Source
    }
  }

  return $null
}

function Get-FirstLine([scriptblock]$Script) {
  try {
    return (& $Script | Select-Object -First 1)
  } catch {
    return $null
  }
}

$ghPath = Get-ExecutablePath -Candidates @(
  'C:\Program Files\GitHub CLI\gh.exe',
  (Join-Path $env:LOCALAPPDATA 'Programs\GitHub CLI\gh.exe')
) -CommandName 'gh.exe'

$gitPath = Get-ExecutablePath -Candidates @(
  'C:\Program Files\Git\cmd\git.exe',
  'C:\Program Files\Git\bin\git.exe'
) -CommandName 'git.exe'

$ghAuth = $null
if ($ghPath) {
  try {
    $ghAuth = (& $ghPath auth status 2>&1) -join "`n"
  } catch {
    $ghAuth = $_.Exception.Message
  }
}

$gcmVersion = $null
$gcmAccounts = $null
if ($gitPath) {
  $gcmVersion = Get-FirstLine { git credential-manager --version }
  try {
    $gcmAccounts = (& git credential-manager github list 2>&1) -join "`n"
  } catch {
    $gcmAccounts = $_.Exception.Message
  }
}

[pscustomobject]@{
  gh_path = $ghPath
  gh_version = if ($ghPath) { Get-FirstLine { & $ghPath --version } } else { $null }
  git_path = $gitPath
  git_version = if ($gitPath) { Get-FirstLine { git --version } } else { $null }
  gcm_path = if ($gcmVersion) { 'git credential-manager' } else { $null }
  gcm_version = $gcmVersion
  credential_helper = (git config --global --get credential.helper) -join "`n"
  gh_auth_status = $ghAuth
  gcm_github_accounts = $gcmAccounts
} | ConvertTo-Json -Depth 4
