$myshell = New-Object -com "Wscript.Shell"
for ($i = 0; $i -lt 600; $i++) {
    Start-Sleep -Seconds 60
    $myshell.sendkeys("{F13}")
}
