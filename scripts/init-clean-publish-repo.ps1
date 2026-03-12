param(
  [Parameter(Mandatory = $true)]
  [string]$SourceDir,

  [Parameter(Mandatory = $true)]
  [string]$DestDir,

  [string]$CommitMessage = 'chore: initialize publish repository'
)

$ErrorActionPreference = 'Stop'

trap {
  Write-Error $_
  exit 1
}

function Invoke-Git {
  param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
  )

  function Quote-Arg([string]$Arg) {
    if ($null -eq $Arg) {
      return '""'
    }
    if ($Arg -match '[\s"]') {
      return '"' + ($Arg -replace '"', '\"') + '"'
    }
    return $Arg
  }

  $gitCmd = Get-Command git.exe -ErrorAction Stop
  $stdoutFile = [System.IO.Path]::GetTempFileName()
  $stderrFile = [System.IO.Path]::GetTempFileName()

  try {
    $argumentLine = ($Arguments | ForEach-Object { Quote-Arg $_ }) -join ' '
    $proc = Start-Process -FilePath $gitCmd.Source -ArgumentList $argumentLine -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
    $stdout = if ((Get-Item $stdoutFile).Length -gt 0) { Get-Content $stdoutFile -Raw } else { '' }
    $stderr = if ((Get-Item $stderrFile).Length -gt 0) { Get-Content $stderrFile -Raw } else { '' }

    if ($proc.ExitCode -ne 0) {
      $message = (($stdout, $stderr) -join "`n").Trim()
      if (-not $message) {
        $message = "git command failed: git $($Arguments -join ' ')"
      }
      throw $message
    }

    if ($stdout) {
      return ($stdout -split "`r?`n" | Where-Object { $_ -ne '' })
    }

    return @()
  }
  finally {
    Remove-Item -Force $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
  }
}

function Copy-DirectoryTree {
  param(
    [string]$From,
    [string]$To
  )

  $excludeNames = @('.git', 'node_modules', '__pycache__')
  $excludeSuffixes = @('.pyc')

  Get-ChildItem -LiteralPath $From -Force | ForEach-Object {
    if ($excludeNames -contains $_.Name) {
      return
    }

    $target = Join-Path $To $_.Name
    if ($_.PSIsContainer) {
      New-Item -ItemType Directory -Path $target -Force | Out-Null
      Copy-DirectoryTree -From $_.FullName -To $target
      return
    }

    if ($excludeSuffixes -contains $_.Extension) {
      return
    }

    Copy-Item -LiteralPath $_.FullName -Destination $target -Force
  }
}

$resolvedSource = (Resolve-Path $SourceDir).Path
if (-not (Test-Path $resolvedSource)) {
  throw "Source directory not found: $SourceDir"
}

if (Test-Path $DestDir) {
  throw "Destination already exists: $DestDir"
}

New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
Copy-DirectoryTree -From $resolvedSource -To $DestDir

Invoke-Git init $DestDir | Out-Null
Invoke-Git config --global --add safe.directory (Resolve-Path $DestDir).Path | Out-Null
Invoke-Git -C $DestDir config user.name 'Codex Agent' | Out-Null
Invoke-Git -C $DestDir config user.email 'codex-agent@local' | Out-Null
Invoke-Git -C $DestDir symbolic-ref HEAD refs/heads/main | Out-Null
Invoke-Git -C $DestDir add . | Out-Null
Invoke-Git -C $DestDir commit -m $CommitMessage | Out-Null

$topLevel = (Invoke-Git -C $DestDir rev-parse --show-toplevel | Select-Object -First 1).Trim()
$normalizedTopLevel = ($topLevel -replace '\\', '/').TrimEnd('/')
$normalizedDest = (((Resolve-Path $DestDir).Path) -replace '\\', '/').TrimEnd('/')
if ($normalizedTopLevel -ne $normalizedDest) {
  throw "Destination is not a standalone Git repository: $DestDir"
}

[pscustomobject]@{
  source = $resolvedSource
  destination = (Resolve-Path $DestDir).Path
  branch = 'main'
  commit = (Invoke-Git -C $DestDir rev-parse --short HEAD | Select-Object -First 1).Trim()
} | ConvertTo-Json -Depth 3
