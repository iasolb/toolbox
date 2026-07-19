param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

. (Join-Path $PSScriptRoot 'common.ps1')
$config = Import-MachineSyncConfig

function Show-Usage {
    Write-Host 'Usage: push.mac.claude <path> --to <mac path> [--csv]'
    Write-Host "  <path> resolves against the claude working dir ($($config.ClaudeDir)) unless rooted."
    Write-Host "  --to is the Mac parent directory, resolved against $($config.PeerRoot) unless absolute or ~/."
    Write-Host '  The pushed item lands at <to>/<leaf> on the Mac. Existing destination requires a y/N confirm.'
    Write-Host '  --csv runs transferred .csv files through the UTF-8 ensurer on the Mac afterwards.'
}

$PathArg = $null
$ToArg = $null
$Csv = $false
$showHelp = $false

if ($RemainingArgs) {
    for ($i = 0; $i -lt $RemainingArgs.Count; $i++) {
        $current = $RemainingArgs[$i]
        switch ($current) {
            '--to' {
                $i++
                if ($i -ge $RemainingArgs.Count) { throw 'Missing value after --to' }
                $ToArg = $RemainingArgs[$i]
            }
            '--csv' { $Csv = $true }
            '--help' { $showHelp = $true }
            '-h' { $showHelp = $true }
            default {
                if ($PathArg) { throw 'push.mac.claude takes exactly one path argument.' }
                $PathArg = $current
            }
        }
    }
}

if ($showHelp) {
    Show-Usage
    exit 0
}

if (-not $PathArg) {
    Show-Usage
    exit 1
}

if (-not $ToArg) {
    Write-Host 'push.mac.claude requires --to <mac path>. Nothing was pushed.' -ForegroundColor Red
    Show-Usage
    exit 1
}

Invoke-MachineSyncPush -Config $config -LocalBase $config.ClaudeDir -FromValue $PathArg -ToValue $ToArg -Csv $Csv -CommandName 'push.mac.claude'
