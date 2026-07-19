param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

. (Join-Path $PSScriptRoot 'common.ps1')
$config = Import-MachineSyncConfig

function Show-Usage {
    Write-Host 'Usage: push.mac --from <pc path> --to <mac path> [--csv]'
    Write-Host "  --from resolves against $($config.LocalRoot) unless rooted."
    Write-Host "  --to is the Mac parent directory, resolved against $($config.PeerRoot) unless absolute or ~/."
    Write-Host '  The pushed item lands at <to>/<leaf> on the Mac. Existing destination requires a y/N confirm.'
    Write-Host '  --csv runs transferred .csv files through the UTF-8 ensurer on the Mac afterwards.'
}

$FromArg = $null
$ToArg = $null
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
            '--to' {
                $i++
                if ($i -ge $RemainingArgs.Count) { throw 'Missing value after --to' }
                $ToArg = $RemainingArgs[$i]
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
    Write-Host 'push.mac requires --from <pc path>. Nothing was pushed.' -ForegroundColor Red
    Show-Usage
    exit 1
}

if (-not $ToArg) {
    Write-Host 'push.mac requires --to <mac path>. Nothing was pushed.' -ForegroundColor Red
    Show-Usage
    exit 1
}

Invoke-MachineSyncPush -Config $config -LocalBase $config.LocalRoot -FromValue $FromArg -ToValue $ToArg -Csv $Csv -CommandName 'push.mac'
