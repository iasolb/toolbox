# One-time PC install: adds the machine-sync functions to $PROFILE and seeds
# the user config. Safe to re-run (replaces its own profile block in place).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoPowershell = (Resolve-Path (Join-Path $PSScriptRoot '..\powershell')).Path
$marker = '# >>> machine-sync >>>'
$endMarker = '# <<< machine-sync <<<'

$block = @"
$marker
function pull.mac { & '$repoPowershell\pull.mac.ps1' @args }
function push.mac { & '$repoPowershell\push.mac.ps1' @args }
function pull.mac.claude { & '$repoPowershell\pull.mac.claude.ps1' @args }
function push.mac.claude { & '$repoPowershell\push.mac.claude.ps1' @args }
$endMarker
"@

if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}
$profileText = Get-Content $PROFILE -Raw
if ($profileText -and $profileText.Contains($marker)) {
    $pattern = [regex]::Escape($marker) + '[\s\S]*?' + [regex]::Escape($endMarker)
    Set-Content -Path $PROFILE -Value ([regex]::Replace($profileText, $pattern, $block.TrimEnd()))
    Write-Host "Replaced machine-sync block in $PROFILE"
} else {
    Add-Content -Path $PROFILE -Value "`n$block"
    Write-Host "Added machine-sync block to $PROFILE"
}

$configDest = Join-Path $HOME '.machine-sync.ps1'
if (-not (Test-Path $configDest)) {
    Copy-Item (Join-Path $PSScriptRoot '..\config\machine-sync.ps1.example') $configDest
    Write-Host "Seeded config at $configDest, edit it before first use."
} else {
    Write-Host "Config already present at $configDest, left untouched."
}

Write-Host 'Reload with: . $PROFILE'
