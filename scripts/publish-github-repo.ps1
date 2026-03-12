param(
  [Parameter(Mandatory = $true)]
  [string]$SourceDir,

  [Parameter(Mandatory = $true)]
  [string]$RepoName,

  [string]$RepoOwner,

  [ValidateSet('public', 'private')]
  [string]$Visibility = 'public',

  [string]$PublishDir,

  [string]$RemoteName = 'origin',

  [string]$RemoteUrl,

  [string]$Branch = 'main',

  [string]$CommitMessage = 'chore: prepare repository for publishing',

  [string]$Description,

  [string[]]$Topics = @(),

  [string]$ReleaseTag,

  [string]$ReleaseTitle,

  [string]$ReleaseNotes = '',

  [string[]]$AssetPaths = @(),

  [switch]$CreateCleanRepo,

  [switch]$ForcePush,

  [switch]$PlanOnly
)

$ErrorActionPreference = 'Stop'

trap {
  Write-Error $_
  exit 1
}

function Normalize-Path {
  param([string]$Path)

  if (-not $Path) {
    return $null
  }

  return (($Path -replace '\\', '/').TrimEnd('/'))
}

function Get-UniquePublishDir {
  param([string]$BasePath)

  if (-not (Test-Path $BasePath)) {
    return $BasePath
  }

  $parent = Split-Path $BasePath -Parent
  $leaf = Split-Path $BasePath -Leaf

  for ($i = 2; $i -le 1000; $i++) {
    $candidate = Join-Path $parent "$leaf-$i"
    if (-not (Test-Path $candidate)) {
      return $candidate
    }
  }

  throw "Could not find an available publish directory for base path: $BasePath"
}

function Get-ExecutablePath {
  param(
    [string[]]$Candidates,
    [string]$CommandName
  )

  foreach ($candidate in $Candidates) {
    if ($candidate -and (Test-Path $candidate)) {
      return $candidate
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

function Ensure-GitHubCliInstalled {
  if ($script:GhPath) {
    return $script:GhPath
  }

  $installScript = Join-Path $PSScriptRoot 'install-gh-windows.ps1'
  if (-not (Test-Path $installScript)) {
    throw "Missing helper script: $installScript"
  }

  Write-Host 'GitHub CLI not found. Installing it now and continuing automatically...'
  $installResult = & powershell -NoProfile -ExecutionPolicy Bypass -File $installScript
  $parsedInstall = $installResult | ConvertFrom-Json
  if (-not $parsedInstall.installed) {
    throw 'GitHub CLI installation did not complete successfully.'
  }

  $script:GhPath = Get-ExecutablePath -Candidates @(
    'C:\Program Files\GitHub CLI\gh.exe',
    (Join-Path $env:LOCALAPPDATA 'Programs\GitHub CLI\gh.exe')
  ) -CommandName 'gh.exe'

  if (-not $script:GhPath) {
    throw 'gh.exe could not be located after installation.'
  }

  return $script:GhPath
}

function Invoke-ExternalTool {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
  )

  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $output = & $FilePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousPreference
  }

  $text = (($output | ForEach-Object { "$_" }) -join "`n").Trim()

  if ($exitCode -ne 0) {
    if (-not $text) {
      $text = "$FilePath failed with exit code $exitCode"
    }
    throw $text
  }

  return [pscustomobject]@{
    StdOut = $text
    StdErr = ''
    Lines = @($output | ForEach-Object { "$_" } | Where-Object { $_ -ne '' })
  }
}

function Invoke-Git {
  param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
  )

  if (-not $script:GitPath) {
    throw 'git.exe is required.'
  }

  return Invoke-ExternalTool -FilePath $script:GitPath @Arguments
}

function Invoke-Gh {
  param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
  )

  if (-not $script:GhPath) {
    Ensure-GitHubCliInstalled | Out-Null
  }

  return Invoke-ExternalTool -FilePath $script:GhPath @Arguments
}

function Get-HttpStatusCode {
  param($ErrorRecord)

  try {
    return [int]$ErrorRecord.Exception.Response.StatusCode.value__
  } catch {
    return $null
  }
}

function Test-GhAuthentication {
  Ensure-GitHubCliInstalled | Out-Null
  try {
    Invoke-Gh -Arguments @('auth', 'status') | Out-Null
    return $true
  } catch {
    return $false
  }
}

function Test-GcmCredential {
  if (-not $script:GitPath) {
    return $false
  }

  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $credentialOutput = ("protocol=https`nhost=github.com`n`n" | & $script:GitPath credential fill 2>&1)
    if ($LASTEXITCODE -ne 0) {
      return $false
    }

    $passwordLine = @($credentialOutput | ForEach-Object { "$_" } | Where-Object { $_ -like 'password=*' } | Select-Object -First 1)
    return [bool]$passwordLine
  }
  finally {
    $ErrorActionPreference = $previousPreference
  }
}

function Ensure-GitHubAuthentication {
  if (Test-GhAuthentication) {
    return 'gh'
  }

  if (Test-GcmCredential) {
    return 'gcm'
  }

  Write-Host 'GitHub auth not found. Opening browser login now and continuing after authorization completes...'

  try {
    Invoke-Git -Arguments @('credential-manager', 'github', 'login', '--browser', '--url', 'https://github.com') | Out-Null
  } catch {
    if (-not $script:GhPath) {
      throw 'Automatic GitHub browser login failed and gh.exe is not available as a fallback.'
    }
  }

  if (Test-GcmCredential) {
    return 'gcm'
  }

  if ($script:GhPath) {
    Ensure-GitHubCliInstalled | Out-Null
    Invoke-Gh -Arguments @('auth', 'login', '--web', '--hostname', 'github.com', '--git-protocol', 'https', '--skip-ssh-key') | Out-Null
    if (Test-GhAuthentication) {
      return 'gh'
    }
    if (Test-GcmCredential) {
      return 'gcm'
    }
  }

  throw 'GitHub authentication could not be established automatically after browser login.'
}

function Get-GitTopLevel {
  param([string]$Path)

  try {
    return ((Invoke-Git -Arguments @('-C', $Path, 'rev-parse', '--show-toplevel')).Lines | Select-Object -First 1)
  } catch {
    return $null
  }
}

function Get-CurrentBranch {
  param([string]$RepoPath)

  try {
    $branch = (Invoke-Git -Arguments @('-C', $RepoPath, 'branch', '--show-current')).Lines | Select-Object -First 1
    return $branch.Trim()
  } catch {
    return ''
  }
}

function Ensure-SafeDirectory {
  param([string]$RepoPath)

  $resolved = (Resolve-Path $RepoPath).Path
  try {
    $existing = @((Invoke-Git -Arguments @('config', '--global', '--get-all', 'safe.directory')).Lines)
  } catch {
    $existing = @()
  }

  if (-not ($existing | Where-Object { (Normalize-Path $_) -eq (Normalize-Path $resolved) })) {
    Invoke-Git -Arguments @('config', '--global', '--add', 'safe.directory', $resolved) | Out-Null
  }
}

function Ensure-GitIdentity {
  param([string]$RepoPath)

  $name = ''
  $email = ''

  try {
    $name = ((Invoke-Git -Arguments @('-C', $RepoPath, 'config', 'user.name')).Lines | Select-Object -First 1).Trim()
  } catch {
    $name = ''
  }

  try {
    $email = ((Invoke-Git -Arguments @('-C', $RepoPath, 'config', 'user.email')).Lines | Select-Object -First 1).Trim()
  } catch {
    $email = ''
  }

  if (-not $name) {
    Invoke-Git -Arguments @('-C', $RepoPath, 'config', 'user.name', 'Codex Agent') | Out-Null
  }

  if (-not $email) {
    Invoke-Git -Arguments @('-C', $RepoPath, 'config', 'user.email', 'codex-agent@local') | Out-Null
  }
}

function Ensure-LocalRepository {
  param(
    [string]$RepoPath,
    [string]$DesiredBranch,
    [string]$Message
  )

  if (-not (Test-Path (Join-Path $RepoPath '.git'))) {
    Invoke-Git -Arguments @('init', $RepoPath) | Out-Null
    Invoke-Git -Arguments @('-C', $RepoPath, 'symbolic-ref', 'HEAD', "refs/heads/$DesiredBranch") | Out-Null
  }

  Ensure-SafeDirectory -RepoPath $RepoPath
  Ensure-GitIdentity -RepoPath $RepoPath

  $currentBranch = Get-CurrentBranch -RepoPath $RepoPath
  if (-not $currentBranch) {
    Invoke-Git -Arguments @('-C', $RepoPath, 'symbolic-ref', 'HEAD', "refs/heads/$DesiredBranch") | Out-Null
    $currentBranch = $DesiredBranch
  }

  Invoke-Git -Arguments @('-C', $RepoPath, 'add', '.') | Out-Null

  $hasHead = $true
  try {
    Invoke-Git -Arguments @('-C', $RepoPath, 'rev-parse', '--verify', 'HEAD') | Out-Null
  } catch {
    $hasHead = $false
  }

  $status = @((Invoke-Git -Arguments @('-C', $RepoPath, 'status', '--short')).Lines)
  if (-not $hasHead -or $status.Count -gt 0) {
    $commitArgs = @('-C', $RepoPath, 'commit', '-m', $Message)
    if (-not $hasHead -and $status.Count -eq 0) {
      $commitArgs += '--allow-empty'
    }
    Invoke-Git -Arguments $commitArgs | Out-Null
  }

  return $currentBranch
}

function Get-GitHubToken {
  if ($script:GitHubToken) {
    return $script:GitHubToken
  }

  $token = $null
  if ($script:GhPath) {
    try {
      $token = ((Invoke-Gh -Arguments @('auth', 'token')).Lines | Select-Object -First 1).Trim()
    } catch {
      $token = $null
    }
  }

  if (-not $token) {
    Ensure-GitHubAuthentication | Out-Null
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      $credentialOutput = ("protocol=https`nhost=github.com`n`n" | & $script:GitPath credential fill 2>&1)
      if ($LASTEXITCODE -eq 0) {
        $passwordLine = @($credentialOutput | ForEach-Object { "$_" } | Where-Object { $_ -like 'password=*' } | Select-Object -First 1)
        if ($passwordLine) {
          $token = $passwordLine.Substring('password='.Length)
        }
      }
    } finally {
      $ErrorActionPreference = $previousPreference
    }
  }

  if (-not $token) {
    throw 'GitHub authentication is not available through gh auth or Git Credential Manager.'
  }

  $script:GitHubToken = $token
  return $script:GitHubToken
}

function Invoke-GitHubApi {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
    [string]$Method,

    [Parameter(Mandatory = $true)]
    [string]$Uri,

    [object]$Body,

    [string]$Accept = 'application/vnd.github+json'
  )

  $headers = @{
    Authorization = "Bearer $(Get-GitHubToken)"
    Accept = $Accept
    'User-Agent' = 'Codex'
  }

  if ($Method -eq 'DELETE') {
    Invoke-WebRequest -UseBasicParsing -Method Delete -Uri $Uri -Headers $headers | Out-Null
    return $null
  }

  if ($null -eq $Body) {
    return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers
  }

  $json = $Body | ConvertTo-Json -Depth 8 -Compress
  return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -Body $json -ContentType 'application/json'
}

function Invoke-GitHubUpload {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Uri,

    [Parameter(Mandatory = $true)]
    [string]$FilePath
  )

  $extension = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
  $contentType = switch ($extension) {
    '.zip' { 'application/zip' }
    '.json' { 'application/json' }
    default { 'application/octet-stream' }
  }

  $headers = @{
    Authorization = "Bearer $(Get-GitHubToken)"
    Accept = 'application/vnd.github+json'
    'User-Agent' = 'Codex'
  }

  $response = Invoke-WebRequest -UseBasicParsing -Method Post -Uri $Uri -Headers $headers -ContentType $contentType -InFile $FilePath
  if ($response.Content) {
    return ($response.Content | ConvertFrom-Json)
  }

  return $null
}

function Get-ViewerLogin {
  return (Invoke-GitHubApi -Method GET -Uri 'https://api.github.com/user').login
}

function Ensure-RemoteRepository {
  param(
    [string]$Owner,
    [string]$Name,
    [string]$RepoVisibility,
    [string]$RepoDescription,
    [string[]]$RepoTopics
  )

  $repoUri = "https://api.github.com/repos/$Owner/$Name"
  $created = $false

  try {
    $repo = Invoke-GitHubApi -Method GET -Uri $repoUri
  } catch {
    $status = Get-HttpStatusCode $_
    if ($status -ne 404) {
      throw
    }

    $viewer = Get-ViewerLogin
    $payload = @{
      name = $Name
      private = ($RepoVisibility -eq 'private')
    }

    if ($RepoDescription) {
      $payload.description = $RepoDescription
    }

    if ($Owner -eq $viewer) {
      $repo = Invoke-GitHubApi -Method POST -Uri 'https://api.github.com/user/repos' -Body $payload
    } else {
      $ownerInfo = Invoke-GitHubApi -Method GET -Uri "https://api.github.com/users/$Owner"
      if ($ownerInfo.type -ne 'Organization') {
        throw "Cannot create repository under '$Owner' with the current account."
      }

      $repo = Invoke-GitHubApi -Method POST -Uri "https://api.github.com/orgs/$Owner/repos" -Body $payload
    }

    $created = $true
  }

  if ($RepoDescription) {
    $repo = Invoke-GitHubApi -Method PATCH -Uri $repoUri -Body @{ description = $RepoDescription }
  }

  if ($RepoTopics -and $RepoTopics.Count -gt 0) {
    Invoke-GitHubApi -Method PUT -Uri "$repoUri/topics" -Body @{ names = $RepoTopics } | Out-Null
  }

  return [pscustomobject]@{
    created = $created
    repo = $repo
  }
}

function Ensure-RemoteConfigured {
  param(
    [string]$RepoPath,
    [string]$Name,
    [string]$Url
  )

  $existingUrl = $null
  try {
    $existingUrl = ((Invoke-Git -Arguments @('-C', $RepoPath, 'remote', 'get-url', $Name)).Lines | Select-Object -First 1).Trim()
  } catch {
    $existingUrl = $null
  }

  if (-not $existingUrl) {
    Invoke-Git -Arguments @('-C', $RepoPath, 'remote', 'add', $Name, $Url) | Out-Null
    return
  }

  if ((Normalize-Path $existingUrl) -ne (Normalize-Path $Url)) {
    Invoke-Git -Arguments @('-C', $RepoPath, 'remote', 'set-url', $Name, $Url) | Out-Null
  }
}

function Push-Repository {
  param(
    [string]$RepoPath,
    [string]$Remote,
    [string]$PushBranch,
    [bool]$ReplaceRemoteHistory
  )

  $attempts = @(
    @('-C', $RepoPath, '-c', 'http.sslBackend=schannel', 'push', '-u', $Remote, "HEAD:$PushBranch"),
    @('-C', $RepoPath, 'push', '-u', $Remote, "HEAD:$PushBranch")
  )

  if ($ReplaceRemoteHistory) {
    $attempts = @(
      @('-C', $RepoPath, '-c', 'http.sslBackend=schannel', 'push', '--force-with-lease', '-u', $Remote, "HEAD:$PushBranch"),
      @('-C', $RepoPath, 'push', '--force-with-lease', '-u', $Remote, "HEAD:$PushBranch"),
      @('-C', $RepoPath, 'push', '--force', '-u', $Remote, "HEAD:$PushBranch")
    )
  }

  $lastError = $null
  for ($round = 1; $round -le 3; $round++) {
    foreach ($args in $attempts) {
      try {
        Invoke-Git -Arguments $args | Out-Null
        return
      } catch {
        $lastError = $_
      }
    }

    if ($round -lt 3) {
      Start-Sleep -Seconds (3 * $round)
    }
  }

  throw $lastError
}

function Ensure-Release {
  param(
    [string]$Owner,
    [string]$Name,
    [string]$Tag,
    [string]$Title,
    [string]$Notes,
    [string]$TargetBranch,
    [string[]]$Files
  )

  $releaseUri = "https://api.github.com/repos/$Owner/$Name/releases"
  $release = $null
  $created = $false

  try {
    $release = Invoke-GitHubApi -Method GET -Uri "$releaseUri/tags/$Tag"
  } catch {
    $status = Get-HttpStatusCode $_
    if ($status -ne 404) {
      throw
    }

    $release = Invoke-GitHubApi -Method POST -Uri $releaseUri -Body @{
      tag_name = $Tag
      target_commitish = $TargetBranch
      name = $(if ($Title) { $Title } else { $Tag })
      body = $Notes
      draft = $false
      prerelease = $false
    }
    $created = $true
  }

  if (-not $created -and ($Title -or $Notes)) {
    $patchBody = @{}
    if ($Title) {
      $patchBody.name = $Title
    }
    if ($Notes) {
      $patchBody.body = $Notes
    }
    if ($patchBody.Keys.Count -gt 0) {
      $release = Invoke-GitHubApi -Method PATCH -Uri "$releaseUri/$($release.id)" -Body $patchBody
    }
  }

  $uploadedNames = @()
  if ($Files -and $Files.Count -gt 0) {
    foreach ($file in $Files) {
      $resolved = (Resolve-Path $file).Path
      $fileName = [System.IO.Path]::GetFileName($resolved)

      foreach ($asset in @($release.assets | Where-Object { $_.name -eq $fileName })) {
        Invoke-GitHubApi -Method DELETE -Uri "https://api.github.com/repos/$Owner/$Name/releases/assets/$($asset.id)"
      }

      $uploadBase = ($release.upload_url -replace '\{\?name,label\}$', '')
      $uploadUri = '{0}?name={1}' -f $uploadBase, [System.Uri]::EscapeDataString($fileName)
      Invoke-GitHubUpload -Uri $uploadUri -FilePath $resolved | Out-Null
      $uploadedNames += $fileName
    }

    $release = Invoke-GitHubApi -Method GET -Uri "$releaseUri/$($release.id)"
  }

  return [pscustomobject]@{
    created = $created
    release = $release
    uploaded_assets = $uploadedNames
  }
}

if ($AssetPaths.Count -gt 0 -and -not $ReleaseTag) {
  throw 'ReleaseTag is required when AssetPaths are provided.'
}

$Topics = @($Topics | ForEach-Object {
  if ($_ -is [string] -and $_.Contains(',')) {
    $_.Split(',') | ForEach-Object { $_.Trim() }
    return
  }

  "$_".Trim()
} | Where-Object { $_ })

$script:GitPath = Get-ExecutablePath -Candidates @(
  'C:\Program Files\Git\cmd\git.exe',
  'C:\Program Files\Git\bin\git.exe'
) -CommandName 'git.exe'

$script:GhPath = Get-ExecutablePath -Candidates @(
  'C:\Program Files\GitHub CLI\gh.exe',
  (Join-Path $env:LOCALAPPDATA 'Programs\GitHub CLI\gh.exe')
) -CommandName 'gh.exe'

if (-not $script:GitPath) {
  throw 'git.exe is required.'
}

$resolvedSource = (Resolve-Path $SourceDir).Path
$sourceTopLevel = Get-GitTopLevel -Path $resolvedSource
$needsCleanRepo = $CreateCleanRepo.IsPresent
if (-not $needsCleanRepo -and $sourceTopLevel) {
  $needsCleanRepo = (Normalize-Path $sourceTopLevel) -ne (Normalize-Path $resolvedSource)
}

$publishRepository = $resolvedSource
$createdCleanRepo = $false
if ($needsCleanRepo -and -not $PublishDir) {
  $folderName = [System.IO.Path]::GetFileName($resolvedSource)
  $defaultPublishDir = Join-Path (Split-Path $resolvedSource -Parent) "$folderName-publish"
  $PublishDir = Get-UniquePublishDir -BasePath $defaultPublishDir
}

if ($ReleaseTag -and -not $ReleaseTitle) {
  $ReleaseTitle = $ReleaseTag
}

$ghAuthenticated = $false
if ($script:GhPath) {
  $ghAuthenticated = Test-GhAuthentication
}

$authMode = $(if ($ghAuthenticated) { 'gh' } elseif (Test-GcmCredential) { 'gcm' } else { 'none' })

if (-not $RepoOwner) {
  try {
    $RepoOwner = Get-ViewerLogin
  } catch {
    $RepoOwner = $null
  }
}

if (-not $RemoteUrl) {
  if (-not $RepoOwner) {
    if ($PlanOnly) {
      $RepoOwner = '<owner-required>'
    } else {
      throw 'RepoOwner is required when RemoteUrl is not provided and gh auth is unavailable.'
    }
  }
  $RemoteUrl = "https://github.com/$RepoOwner/$RepoName.git"
}

if ($PlanOnly) {
  [pscustomobject]@{
    source = $resolvedSource
    publish_repository = $(if ($needsCleanRepo) { $PublishDir } else { $resolvedSource })
    create_clean_repo = $needsCleanRepo
    remote_name = $RemoteName
    remote_url = $RemoteUrl
    repo_name = "$RepoOwner/$RepoName"
    branch = $Branch
    gh_installed = [bool]$script:GhPath
    gh_authenticated = $ghAuthenticated
    auth_mode = $authMode
    will_create_remote = [bool](-not $PSBoundParameters.ContainsKey('RemoteUrl'))
    will_create_release = [bool]$ReleaseTag
    force_push = [bool]$ForcePush
    asset_count = $AssetPaths.Count
  } | ConvertTo-Json -Depth 4
  exit 0
}

if ($needsCleanRepo) {
  $initScript = Join-Path $PSScriptRoot 'init-clean-publish-repo.ps1'
  if (-not (Test-Path $initScript)) {
    throw "Missing helper script: $initScript"
  }

  $initResult = & powershell -NoProfile -ExecutionPolicy Bypass -File $initScript -SourceDir $resolvedSource -DestDir $PublishDir -CommitMessage $CommitMessage
  $parsedInit = $initResult | ConvertFrom-Json
  $publishRepository = $parsedInit.destination
  $createdCleanRepo = $true
  $Branch = $parsedInit.branch
} else {
  $publishRepository = $resolvedSource
  $Branch = Ensure-LocalRepository -RepoPath $publishRepository -DesiredBranch $Branch -Message $CommitMessage
}

$remoteResult = $null
if (-not $PSBoundParameters.ContainsKey('RemoteUrl')) {
  $authMode = Ensure-GitHubAuthentication
  $remoteResult = Ensure-RemoteRepository -Owner $RepoOwner -Name $RepoName -RepoVisibility $Visibility -RepoDescription $Description -RepoTopics $Topics
}

Ensure-RemoteConfigured -RepoPath $publishRepository -Name $RemoteName -Url $RemoteUrl
Push-Repository -RepoPath $publishRepository -Remote $RemoteName -PushBranch $Branch -ReplaceRemoteHistory $ForcePush.IsPresent

$releaseResult = $null
if ($ReleaseTag) {
  $authMode = Ensure-GitHubAuthentication
  $releaseResult = Ensure-Release -Owner $RepoOwner -Name $RepoName -Tag $ReleaseTag -Title $ReleaseTitle -Notes $ReleaseNotes -TargetBranch $Branch -Files $AssetPaths
}

[pscustomobject]@{
  source = $resolvedSource
  publish_repository = (Resolve-Path $publishRepository).Path
  created_clean_repo = $createdCleanRepo
  remote_name = $RemoteName
  remote_url = $RemoteUrl
  repo_name = $(if ($RepoOwner) { "$RepoOwner/$RepoName" } else { $RepoName })
  branch = $Branch
  auth_mode = $authMode
  remote_created = $(if ($remoteResult) { $remoteResult.created } else { $false })
  repo_url = $(if ($remoteResult) { $remoteResult.repo.html_url } else { $null })
  release_url = $(if ($releaseResult) { $releaseResult.release.html_url } else { $null })
  uploaded_assets = $(if ($releaseResult) { $releaseResult.uploaded_assets } else { @() })
} | ConvertTo-Json -Depth 5
