# insecure priviledge
function Grant-Privilege {
    param([string]$Account, [string]$Privilege)
    $tmp = "$env:TEMP\secpol.cfg"
    secedit /export /cfg $tmp /areas USER_RIGHTS | Out-Null
    $content = Get-Content $tmp
    if ($content -match "^$Privilege\s*=") {
        $content = $content -replace "^($Privilege\s*=.*)", "`$1,$Account"
    } else {
        $content += "$Privilege = $Account"
    }
    $content | Set-Content $tmp
    secedit /configure /db "$env:TEMP\secpol.sdb" /cfg $tmp /areas USER_RIGHTS | Out-Null
    Remove-Item $tmp, "$env:TEMP\secpol.sdb" -ErrorAction SilentlyContinue
    gpupdate /force | Out-Null
}

Grant-Privilege -Account "lowuser" -Privilege "SeDebugPrivilege"
Grant-Privilege -Account "lowuser" -Privilege "SeBackupPrivilege"
Grant-Privilege -Account "lowuser" -Privilege "SeRestorePrivilege"
Grant-Privilege -Account "lowuser" -Privilege "SeLoadDriverPrivilege"
Grant-Privilege -Account "lowuser" -Privilege "SeManageVolumePrivilege"
Grant-Privilege -Account "lowuser" -Privilege "SeTakeOwnershipPrivilege"
Grant-Privilege -Account "svcuser" -Privilege "SeImpersonatePrivilege"
Grant-Privilege -Account "svcuser" -Privilege "SeAssignPrimaryTokenPrivilege"

# unquoted service path
New-Item -ItemType Directory -Path "C:\Vuln Path\Sub Folder" -Force
Copy-Item C:\Windows\System32\cmd.exe "C:\Vuln Path\Sub Folder\service.exe"
sc.exe create VulnUnquoted binPath= C:\Vuln` Path\Sub` Folder\service.exe start= auto
icacls "C:\" /grant "Users:(OI)(CI)M"
icacls "C:\Vuln Path" /grant "Users:(OI)(CI)M"

# writable service
New-Item -ItemType Directory -Path "C:\VulnSvc" -Force
Copy-Item C:\Windows\System32\cmd.exe "C:\VulnSvc\vulnsvc.exe"
New-Service -Name "VulnSvcWrite" -BinaryPathName "C:\VulnSvc\vulnsvc.exe" -StartupType Automatic
icacls "C:\VulnSvc\vulnsvc.exe" /grant "Users:(M)"
icacls "C:\VulnSvc" /grant "Users:(OI)(CI)M"
$acl = Get-Acl "HKLM:\SYSTEM\CurrentControlSet\Services\VulnSvcWrite"
$rule = New-Object System.Security.AccessControl.RegistryAccessRule("Users","FullControl","ContainerInherit","None","Allow")
$acl.SetAccessRule($rule)
Set-Acl "HKLM:\SYSTEM\CurrentControlSet\Services\VulnSvcWrite" $acl

# writable scheduled task
New-Item -ItemType Directory -Path "C:\VulnTask" -Force
@"
@echo off
echo Task executed at %DATE% %TIME% >> C:\VulnTask\log.txt
"@ | Out-File -Encoding ASCII "C:\VulnTask\task.bat"
icacls "C:\VulnTask" /grant "Users:(OI)(CI)M"
icacls "C:\VulnTask\task.bat" /grant "Users:(M)"
$action = New-ScheduledTaskAction -Execute "C:\VulnTask\task.bat"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName "VulnTask" -Action $action -Trigger $trigger -User "SYSTEM" -RunLevel Highest

# AlwaysInstallElevated
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer" -Name "AlwaysInstallElevated" -Type DWord -Value 1
New-Item -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Installer" -Force | Out-Null
Set-ItemProperty -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Installer" -Name "AlwaysInstallElevated" -Type DWord -Value 1

# SAM/SYSTEM backup
New-Item -ItemType Directory -Path "C:\Backup" -Force
reg save HKLM\SAM C:\Backup\SAM.hive
reg save HKLM\SYSTEM C:\Backup\SYSTEM.hive
reg save HKLM\SECURITY C:\Backup\SECURITY.hive
icacls "C:\Backup" /grant "Users:(OI)(CI)R"

# Winlogon AutoLogon
$winlogon = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty -Path $winlogon -Name "AutoAdminLogon" -Value "1" -Type String
Set-ItemProperty -Path $winlogon -Name "DefaultUserName" -Value "serviceuser" -Type String
Set-ItemProperty -Path $winlogon -Name "DefaultPassword" -Value "Se4v1ceUse4" -Type String
Set-ItemProperty -Path $winlogon -Name "DefaultDomainName" -Value $env:COMPUTERNAME -Type String

# DLL Hijacking (writable PATH)
New-Item -ItemType Directory -Path "C:\CustomTools" -Force
icacls "C:\CustomTools" /grant "Users:(OI)(CI)M"
$oldPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
[Environment]::SetEnvironmentVariable("Path", "C:\CustomTools;$oldPath", "Machine")

# writable Run registory key
$key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$acl = Get-Acl $key
$rule = New-Object System.Security.AccessControl.RegistryAccessRule("Users","FullControl","ContainerInherit","None","Allow")
$acl.SetAccessRule($rule)
Set-Acl $key $acl

# writable startup folder
icacls "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp" /grant "Users:(OI)(CI)M"

# SSH private key planted in lowuser profile (T1552.004 Unsecured Credentials: Private Keys)
$lowSsh = "C:\Users\lowuser\.ssh"
New-Item -ItemType Directory -Path $lowSsh -Force | Out-Null
ssh-keygen -t ed25519 -f "$lowSsh\id_ed25519_prod" -N '""' -C "prod-admin@internal" | Out-Null
ssh-keygen -t rsa -b 2048 -f "$lowSsh\id_rsa_backup" -N '""' -C "backup@fileserver" | Out-Null
@"
# Stashed keys for maintenance work.
# id_ed25519_prod : prod-admin@prod-01.internal
# id_rsa_backup   : backup@fileserver.internal (passphrase in KeePass)
"@ | Out-File -Encoding ASCII "$lowSsh\README.txt"
icacls $lowSsh /grant "lowuser:(OI)(CI)F" | Out-Null

# Dummy PuTTY .ppk and cert+password memo
New-Item -ItemType Directory -Path "C:\Users\lowuser\Documents\Keys" -Force | Out-Null
@"
PuTTY-User-Key-File-3: ssh-ed25519
Encryption: none
Comment: admin@server-02
Public-Lines: 2
AAAAC3NzaC1lZDI1NTE5AAAAIExample/Placeholder/Key/For/Lab/Use+Only==
AAAA
Private-Lines: 1
AAAAIExampleLabPrivateKeyMaterial/NotReal/DoNotUse+Placeholder==
Private-MAC: 0000000000000000000000000000000000000000000000000000000000000000
"@ | Out-File -Encoding ASCII "C:\Users\lowuser\Documents\Keys\admin_server.ppk"

@"
Certificate: internal-ca.pfx
Password : CertP@ss2024!
Issued   : 2024-01-10
Renewed  : N/A
"@ | Out-File -Encoding ASCII "C:\Users\Public\Documents\cert_readme.txt"

# OpenSSH Server + writable authorized_keys (T1098.004 Account Manipulation: SSH Authorized Keys)
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue | Out-Null
Start-Service sshd -ErrorAction SilentlyContinue
Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue

# administrators_authorized_keys : writable by any user
$adminAuth = "C:\ProgramData\ssh\administrators_authorized_keys"
if (-not (Test-Path "C:\ProgramData\ssh")) { New-Item -ItemType Directory -Path "C:\ProgramData\ssh" -Force | Out-Null }
New-Item -ItemType File -Path $adminAuth -Force | Out-Null
icacls $adminAuth /inheritance:r | Out-Null
icacls $adminAuth /grant "NT AUTHORITY\SYSTEM:(F)" "BUILTIN\Administrators:(F)" "Users:(M)" | Out-Null

# lowuser's authorized_keys : writable by Everyone
$userAuth = "C:\Users\lowuser\.ssh\authorized_keys"
New-Item -ItemType File -Path $userAuth -Force | Out-Null
icacls $userAuth /grant "Everyone:(M)" | Out-Null
