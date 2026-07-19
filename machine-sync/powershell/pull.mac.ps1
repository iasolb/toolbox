param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

. (Join-Path $PSScriptRoot 'common.ps1')
$config = Import-MachineSyncConfig

function Show-Usage {
    Write-Host 'Usage: pull.mac --from <mac path> --to <pc path> [--csv]'
    Write-Host "  --from resolves against the Mac root ($($config.PeerRoot)) unless absolute or ~/."
    Write-Host "  --to is the PC parent directory, resolved against $($config.LocalRoot) unless rooted."
    Write-Host '  The pulled item lands at <to>\<leaf>. Existing same-name files are overwritten.'
    Write-Host '  --csv runs transferred .csv files through the UTF-8 ensurer afterwards.'
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
    Write-Host 'pull.mac requires --from <mac path>. Nothing was pulled.' -ForegroundColor Red
    Show-Usage
    exit 1
}

if (-not $ToArg) {
    Write-Host 'pull.mac requires --to <pc path>. Nothing was pulled.' -ForegroundColor Red
    Show-Usage
    exit 1
}

$destDir = Resolve-LocalPath $config.LocalRoot $ToArg
Invoke-MachineSyncPull -Config $config -FromValue $FromArg -DestDir $destDir -Csv $Csv -CommandName 'pull.mac'
