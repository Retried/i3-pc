#!/bin/bash
# Lists display driver fault reports (LiveKernelEvent 117 / 141) of the last N minutes (default 30).
powershell -NoProfile -Command "\$since=(Get-Date).AddMinutes(-${1:-30}); \$e=Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=\$since} -ErrorAction SilentlyContinue | Where-Object { \$_.Message -match 'LiveKernelEvent' -and \$_.Message -match '\b(117|141)\b' }; if (\$e) { \$e | ForEach-Object { '{0:HH:mm:ss} {1}' -f \$_.TimeCreated, (\$_.Message -split \"\`n\")[0] } } else { 'no driver fault events' }"
