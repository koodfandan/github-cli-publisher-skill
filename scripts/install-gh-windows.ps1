param(
  [switch]$ForceMsi
)

$ErrorActionPreference = 'Stop'

function Get-GhPath {
  $candidates = @(
    'C:\Program Files\GitHub CLI\gh.exe',
    (Join-Path $env:LOCALAPPDATA 'Programs\GitHub CLI\gh.exe')
  )

  foreach ($path in $candidates) {
    if (Test-Path $path) {
      return $path
    }
  }

  $cmd = Get-Command gh.exe -ErrorAction SilentlyContinue
  if ($cmd) {
    return $cmd.Source
  }

  return $null
}

function Get-ArchSuffix {
  if ([Environment]::Is64BitOperatingSystem) {
    return 'windows_amd64.msi'
  }
  return 'windows_386.msi'
}

$existing = Get-GhPath
if ($existing -and -not $ForceMsi) {
  $version = & $existing --version | Select-Object -First 1
  [pscustomobject]@{
    installed = $true
    method = 'existing'
    path = $existing
    version = $version
  } | ConvertTo-Json -Depth 3
  exit 0
}

$installed = $false
$method = $null
$winget = Get-Command winget.exe -ErrorAction SilentlyContinue

if ($winget -and -not $ForceMsi) {
  try {
    & $winget.Source install --id GitHub.cli --source winget --scope user --accept-package-agreements --accept-source-agreements | Out-Null
    $installed = $true
    $method = 'winget'
  } catch {
    $installed = $false
  }
}

if (-not $installed) {
  $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/cli/cli/releases/latest' -Headers @{ 'User-Agent' = 'Codex' }
  $suffix = Get-ArchSuffix
  $asset = $release.assets | Where-Object { $_.name -like "*$suffix" } | Select-Object -First 1
  if (-not $asset) {
    throw "Could not find a matching GitHub CLI MSI asset for suffix '$suffix'."
  }

  $tempFile = Join-Path $env:TEMP $asset.name
  Invoke-WebRequest -UseBasicParsing $asset.browser_download_url -OutFile $tempFile
  $proc = Start-Process msiexec.exe -ArgumentList @('/i', $tempFile, '/qn', '/norestart') -Wait -PassThru
  if ($proc.ExitCode -ne 0) {
    throw "msiexec failed with exit code $($proc.ExitCode)"
  }
  $method = 'msi'
}

$ghPath = Get-GhPath
if (-not $ghPath) {
  throw 'gh.exe not found after installation.'
}

$version = & $ghPath --version | Select-Object -First 1
[pscustomobject]@{
  installed = $true
  method = $method
  path = $ghPath
  version = $version
} | ConvertTo-Json -Depth 3
