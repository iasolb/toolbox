Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Git for Windows can shadow the native OpenSSH client on PATH, and its ssh
# cannot resolve .local mDNS names (the Mac's stable address), so pin the
# native client explicitly. Paths contain no spaces on purpose: these get
# embedded unquoted in cmd.exe pipelines, where a leading quoted token
# triggers cmd's outer-quote stripping.
$NativeOpenSsh = Join-Path $env:SystemRoot 'System32\OpenSSH'
$SshExe = if (Test-Path (Join-Path $NativeOpenSsh 'ssh.exe')) { Join-Path $NativeOpenSsh 'ssh.exe' } else { 'ssh' }
$ScpExe = if (Test-Path (Join-Path $NativeOpenSsh 'scp.exe')) { Join-Path $NativeOpenSsh 'scp.exe' } else { 'scp' }

function Get-MachineSyncConfigPath {
    if ($env:MACHINE_SYNC_CONFIG) {
        return $env:MACHINE_SYNC_CONFIG
    }
    return (Join-Path $HOME '.machine-sync.ps1')
}

function Import-MachineSyncConfig {
    $configPath = Get-MachineSyncConfigPath
    if (-not (Test-Path $configPath)) {
        throw "Missing config: $configPath. Copy machine-sync/config/machine-sync.ps1.example there and edit it."
    }

    . $configPath

    foreach ($name in 'PeerHost', 'PeerRoot', 'LocalRoot', 'ClaudeDir') {
        $var = Get-Variable -Name $name -ErrorAction SilentlyContinue
        if (-not $var -or -not $var.Value) {
            throw "$name must be set in $configPath"
        }
    }

    return @{
        PeerHost    = $PeerHost
        PeerRoot    = ($PeerRoot -replace '\\', '/').TrimEnd('/')
        LocalRoot   = $LocalRoot.TrimEnd('\', '/')
        ClaudeDir   = $ClaudeDir.TrimEnd('\', '/')
        ToolboxRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    }
}

function Get-MachineSyncIgnorePath {
    if ($env:MACHINE_SYNC_IGNORE) {
        return $env:MACHINE_SYNC_IGNORE
    }
    $userIgnore = Join-Path $HOME '.machinesync-ignore'
    if (Test-Path $userIgnore) {
        return $userIgnore
    }
    return (Join-Path $PSScriptRoot '..\config\.machinesync-ignore.example')
}

function Get-ExcludePatterns {
    $path = Get-MachineSyncIgnorePath
    if (-not (Test-Path $path)) {
        return @()
    }
    $patterns = @()
    foreach ($rawLine in Get-Content $path) {
        $line = ($rawLine -split '#')[0].Trim()
        if ($line) {
            $patterns += $line
        }
    }
    return $patterns
}

# Resolves a peer (Mac) path: absolute and ~/ paths pass through, everything
# else is joined onto PeerRoot. PeerRoot itself may be relative to the remote
# home dir, which is where ssh commands land anyway.
function Resolve-PeerPath {
    param([string]$PeerRoot, [string]$Value)
    $clean = ($Value -replace '\\', '/').TrimEnd('/')
    if ($clean.StartsWith('~/')) { return $clean.Substring(2) }
    if ($clean.StartsWith('/')) { return $clean }
    if (-not $clean -or $clean -eq '.') { return $PeerRoot }
    return "$PeerRoot/$clean"
}

function Resolve-LocalPath {
    param([string]$LocalBase, [string]$Value)
    if (-not $Value -or $Value -eq '.') { return $LocalBase }
    if ([System.IO.Path]::IsPathRooted($Value)) { return $Value }
    return Join-Path $LocalBase ($Value -replace '/', '\')
}

function Split-PeerPath {
    param([string]$Path)
    $trimmed = $Path.TrimEnd('/')
    $idx = $trimmed.LastIndexOf('/')
    if ($idx -lt 0) {
        # single segment relative to the remote home dir
        return @{ Parent = '.'; Leaf = $trimmed }
    }
    $parent = $trimmed.Substring(0, $idx)
    if (-not $parent) { $parent = '/' }
    return @{ Parent = $parent; Leaf = $trimmed.Substring($idx + 1) }
}

function Test-PeerDirectory {
    param([string]$PeerHost, [string]$RemotePath)
    & $SshExe $PeerHost "test -d '$RemotePath'" | Out-Null
    return $LASTEXITCODE -eq 0
}

function Test-PeerExists {
    param([string]$PeerHost, [string]$RemotePath)
    & $SshExe $PeerHost "test -e '$RemotePath'" | Out-Null
    return $LASTEXITCODE -eq 0
}

# Confirm-PushDestination checks whether RemoteTarget already exists on the
# peer. If it does, it shows the current contents and requires an explicit
# y/N before letting the caller continue, exiting (without pushing) on
# anything else.
function Confirm-PushDestination {
    param([string]$PeerHost, [string]$RemoteTarget)

    if (-not (Test-PeerExists $PeerHost $RemoteTarget)) {
        return
    }

    Write-Host "Destination already exists: ${PeerHost}:$RemoteTarget" -ForegroundColor Yellow
    Write-Host 'Current contents there:'
    & $SshExe $PeerHost "ls -la '$RemoteTarget'"
    Write-Host ''
    Write-Host 'This push will overwrite any file with a matching name.'
    Write-Host 'Anything already there that is NOT part of this push is left as-is (not deleted).'
    Write-Host ''

    $reply = Read-Host 'Continue with push? [y/N]'
    if ($reply -notmatch '^(?i:y|yes)$') {
        Write-Host 'Aborted, nothing was pushed.' -ForegroundColor Red
        exit 1
    }
}

function Get-ExcludeFlagString {
    param([string[]]$ExcludePatterns, [string]$QuoteChar)
    $flags = ''
    foreach ($p in $ExcludePatterns) {
        $flags += " --exclude=$QuoteChar$p$QuoteChar"
    }
    return $flags
}

# Invoke-TarPull streams a filtered tar of <RemoteParent>/<RemoteLeaf> over SSH
# and extracts it into <LocalDest>. The pipe runs through cmd.exe so the
# OS-level pipe carries raw bytes: PowerShell's own pipeline mangles binary
# data (like gzip streams) passed between two native executables.
function Invoke-TarPull {
    param(
        [string]$PeerHost,
        [string]$RemoteParent,
        [string]$RemoteLeaf,
        [string]$LocalDest,
        [string[]]$ExcludePatterns
    )
    if (-not (Test-Path $LocalDest)) {
        New-Item -ItemType Directory -Path $LocalDest -Force | Out-Null
    }
    # remote shell is POSIX, so single-quoted excludes are safe there
    $excludeStr = Get-ExcludeFlagString $ExcludePatterns "'"
    $remoteCmd = "tar -czf -$excludeStr -C '$RemoteParent' '$RemoteLeaf'"
    $cmdLine = "$SshExe $PeerHost `"$remoteCmd`" | tar -xzf - -C `"$LocalDest`""
    cmd /c $cmdLine
    if ($LASTEXITCODE -ne 0) {
        throw "tar pull failed (exit $LASTEXITCODE)"
    }
}

# Invoke-TarPush mirrors Invoke-TarPull: filters locally, streams to the peer,
# and extracts into <RemoteDest> (which must already exist).
function Invoke-TarPush {
    param(
        [string]$PeerHost,
        [string]$LocalParent,
        [string]$LocalLeaf,
        [string]$RemoteDest,
        [string[]]$ExcludePatterns
    )
    # local tar runs under cmd.exe, which treats single quotes as literal
    # characters, so local excludes must be double-quoted
    $excludeStr = Get-ExcludeFlagString $ExcludePatterns '"'
    $cmdLine = "tar -czf -$excludeStr -C `"$LocalParent`" `"$LocalLeaf`" | $SshExe $PeerHost `"tar -xzf - -C '$RemoteDest'`""
    cmd /c $cmdLine
    if ($LASTEXITCODE -ne 0) {
        throw "tar push failed (exit $LASTEXITCODE)"
    }
}

function Invoke-CsvEnsureLocal {
    param([string]$TargetPath, [string]$ToolboxRoot)
    $script = Join-Path $ToolboxRoot 'csv-utf8\ensure_utf8.py'
    if (-not (Test-Path $script)) {
        Write-Host "csv-utf8: missing $script, skipping conversion" -ForegroundColor Yellow
        return
    }
    # the Microsoft Store python stub is on PATH even with no real install,
    # so probe with --version instead of trusting Get-Command
    python --version *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'csv-utf8: no working python on this machine, skipping conversion' -ForegroundColor Yellow
        return
    }
    python $script $TargetPath
}

function Invoke-CsvEnsureOnPeer {
    param([string]$PeerHost, [string]$RemotePath, [string]$ToolboxRoot)
    $script = Join-Path $ToolboxRoot 'csv-utf8\ensure_utf8.py'
    if (-not (Test-Path $script)) {
        Write-Host "csv-utf8: missing $script, skipping conversion" -ForegroundColor Yellow
        return
    }
    & $SshExe $PeerHost 'command -v python3' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "csv-utf8: no python3 on $PeerHost, skipping conversion" -ForegroundColor Yellow
        return
    }
    # stream the script over ssh so the peer needs python3 but not this repo
    $cmdLine = "$SshExe $PeerHost `"python3 - '$RemotePath'`" < `"$script`""
    cmd /c $cmdLine
    if ($LASTEXITCODE -ne 0) {
        Write-Host "csv-utf8 on $PeerHost failed (exit $LASTEXITCODE)" -ForegroundColor Yellow
    }
}

# Shared driver for pull.mac / pull.mac.claude: resolve, transfer, optional csv.
function Invoke-MachineSyncPull {
    param(
        [hashtable]$Config,
        [string]$FromValue,
        [string]$DestDir,
        [bool]$Csv,
        [string]$CommandName
    )
    $remoteFull = Resolve-PeerPath $Config.PeerRoot $FromValue
    $split = Split-PeerPath $remoteFull
    if (-not (Test-Path $DestDir)) {
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    }
    $landing = Join-Path $DestDir $split.Leaf
    Write-Host "$CommandName $FromValue -> $landing"
    if (Test-PeerDirectory $Config.PeerHost $remoteFull) {
        Invoke-TarPull -PeerHost $Config.PeerHost -RemoteParent $split.Parent -RemoteLeaf $split.Leaf -LocalDest $DestDir -ExcludePatterns (Get-ExcludePatterns)
    } else {
        & $ScpExe "$($Config.PeerHost):'$remoteFull'" "$DestDir\"
        if ($LASTEXITCODE -ne 0) {
            throw "scp failed (exit $LASTEXITCODE)"
        }
    }
    if ($Csv) {
        Invoke-CsvEnsureLocal -TargetPath $landing -ToolboxRoot $Config.ToolboxRoot
    }
}

# Shared driver for push.mac / push.mac.claude. LocalBase decides what
# relative source paths resolve against (LocalRoot vs ClaudeDir).
function Invoke-MachineSyncPush {
    param(
        [hashtable]$Config,
        [string]$LocalBase,
        [string]$FromValue,
        [string]$ToValue,
        [bool]$Csv,
        [string]$CommandName
    )
    $localFull = Resolve-LocalPath $LocalBase $FromValue
    if (-not (Test-Path $localFull)) {
        throw "Missing local path: $localFull"
    }
    $remoteDest = Resolve-PeerPath $Config.PeerRoot $ToValue
    $leafName = Split-Path $localFull -Leaf
    $finalTarget = "$($remoteDest.TrimEnd('/'))/$leafName"
    Confirm-PushDestination -PeerHost $Config.PeerHost -RemoteTarget $finalTarget

    & $SshExe $Config.PeerHost "mkdir -p '$remoteDest'" | Out-Null

    if (Test-Path $localFull -PathType Container) {
        Write-Host "$CommandName $FromValue -> $($Config.PeerHost):$finalTarget"
        Invoke-TarPush -PeerHost $Config.PeerHost -LocalParent (Split-Path $localFull -Parent) -LocalLeaf $leafName -RemoteDest $remoteDest -ExcludePatterns (Get-ExcludePatterns)
    } else {
        Write-Host "$CommandName $FromValue -> $($Config.PeerHost):$remoteDest/"
        & $ScpExe $localFull "$($Config.PeerHost):'$remoteDest/'"
        if ($LASTEXITCODE -ne 0) {
            throw "scp failed (exit $LASTEXITCODE)"
        }
    }
    if ($Csv) {
        Invoke-CsvEnsureOnPeer -PeerHost $Config.PeerHost -RemotePath $finalTarget -ToolboxRoot $Config.ToolboxRoot
    }
}
