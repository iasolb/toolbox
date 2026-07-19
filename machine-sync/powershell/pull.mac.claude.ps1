param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

. (Join-Path $PSScriptRoot 'common.ps1')
$config = Import-MachineSyncConfig

function Show-Usage {
    Write-Host 'Usage: pull.mac.claude --from <mac path> [--csv]'
    Write-Host "  --from resolves against the Mac root ($($config.PeerRoot)) unless absolute or ~/."
    Write-Host "  Always lands in the claude working dir: $($config.ClaudeDir)\<leaf>."
    Write-Host '  --csv runs transferred .csv files through the UTF-8 ensurer afterwards.'
}

$FromArg = $null
$Csv = $false
$showHelp = $false

if ($RemainingArgs) {
    for ($i = 0; $i -lt $RemainingArgs.Count; $i++) {
        $current = $RemainingArgs[$i]
        switch ($current) {
            '--from' {
                $i++
                if ($i -ge $RemainingArgs.Count) { throw 'Missing value after --from' }
                $FromArg = $RemainingArgs[$i]
            }
            '--csv' { $Csv = $true }
            '--help' { $showHelp = $true }
            '-h' { $showHelp = $true }
            default { throw "Unexpected argument: $current" }
        }
    }
}

if ($showHelp) {
    Show-Usage
    exit 0
}

if (-not $FromArg) {
    Write-Host 'pull.mac.claude requires --from <mac path>. Nothing was pulled.' -ForegroundColor Red
    Show-Usage
    exit 1
}

Invoke-MachineSyncPull -Config $config -FromValue $FromArg -DestDir $config.ClaudeDir -Csv $Csv -CommandName 'pull.mac.claude'
