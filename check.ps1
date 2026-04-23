# check priviledge
whoami /priv
whoami /all

# check service
Get-WmiObject Win32_Service | Where-Object { $_.Name -like "Vuln*" } | Select-Object Name, PathName, StartMode

# check scheduled task
Get-ScheduledTask -TaskName "VulnTask"

# check registory
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword
reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v AlwaysInstallElevated

# check ACL
icacls "C:\VulnSvc\vulnsvc.exe"
icacls "C:\CustomTools"
