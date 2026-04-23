#!/bin/bash

set -u  # error on undefined variables

# ------------------------ Configuration ------------------------
LOWUSER="lowuser"
LOWPASS="*****"
ROOTPASS_FOR_LAB="*****"

# ------------------------ Colored output helpers ------------------------
c_info()  { echo -e "\e[36m[INFO]\e[0m  $*"; }
c_ok()    { echo -e "\e[32m[OK]\e[0m    $*"; }
c_warn()  { echo -e "\e[33m[WARN]\e[0m  $*"; }
c_err()   { echo -e "\e[31m[ERR]\e[0m   $*"; }
c_step()  { echo -e "\n\e[35m=== $* ===\e[0m"; }

# ------------------------ Preflight check ------------------------
if [ "$(id -u)" -ne 0 ]; then
    c_err "This script must be run as root: sudo bash $0"
    exit 1
fi

c_warn "This script intentionally introduces vulnerabilities. Do NOT run outside a lab."
c_warn "Starting in 5 seconds... Press Ctrl+C to abort"
sleep 5

# =============================================================================
# 1. Create user
# =============================================================================
c_step "1. Create lowuser"

if id "$LOWUSER" &>/dev/null; then
    c_info "$LOWUSER already exists"
else
    useradd -m -s /bin/bash "$LOWUSER"
    echo "$LOWUSER:$LOWPASS" | chpasswd
    c_ok "Created $LOWUSER (password: $LOWPASS)"
fi

# Set known root password for the lab
echo "root:$ROOTPASS_FOR_LAB" | chpasswd
c_ok "Root password set to $ROOTPASS_FOR_LAB"

LOWHOME="/home/$LOWUSER"

# =============================================================================
# 2. GTFOBins-style sudo NOPASSWD commands
# =============================================================================
c_step "2. Allow GTFOBins commands via sudo NOPASSWD"

# Classic commands that allow shell escape via sudo
# Reference: https://gtfobins.github.io/
cat > /etc/sudoers.d/vuln_gtfobins <<EOF
# Lab: GTFOBins candidates
# find, less, vim, awk can spawn a shell directly
$LOWUSER ALL=(root) NOPASSWD: /usr/bin/find
$LOWUSER ALL=(root) NOPASSWD: /usr/bin/less
$LOWUSER ALL=(root) NOPASSWD: /usr/bin/vim
$LOWUSER ALL=(root) NOPASSWD: /usr/bin/awk
$LOWUSER ALL=(root) NOPASSWD: /usr/bin/env
EOF
chmod 440 /etc/sudoers.d/vuln_gtfobins
c_ok "sudo NOPASSWD: find, less, vim, awk, env"

# =============================================================================
# 3. Sudoers wildcard (path traversal)
# =============================================================================
c_step "3. Sudoers wildcard leading to path traversal"

# sudo cat /var/log/* pattern. 
cat > /etc/sudoers.d/vuln_wildcard <<EOF
# Classic wildcard misuse
$LOWUSER ALL=(root) NOPASSWD: /usr/bin/cat /var/log/*
EOF
chmod 440 /etc/sudoers.d/vuln_wildcard
c_ok "Configured: sudo cat /var/log/* (path traversal)"

# =============================================================================
# 4. SUID / SGID binaries
# =============================================================================
c_step "4. Deploy SUID/SGID binaries"

# GTFOBins SUID escalation candidates
# find can spawn a shell via --exec
chmod u+s /usr/bin/find 2>/dev/null && c_ok "SUID: /usr/bin/find"

# less can also escape via !sh
[ -f /usr/bin/less ] && chmod u+s /usr/bin/less && c_ok "SUID: /usr/bin/less"

# nmap (older versions had --interactive; other vectors exist)
if [ -f /usr/bin/nmap ]; then
    chmod u+s /usr/bin/nmap
    c_ok "SUID: /usr/bin/nmap"
fi

# python3 SUID is too broad if applied to the main binary,
# so place a copy under /usr/local/bin with SUID
cp /usr/bin/python3 /usr/local/bin/python3-backup 2>/dev/null
if [ -f /usr/local/bin/python3-backup ]; then
    chmod 4755 /usr/local/bin/python3-backup
    c_ok "SUID: /usr/local/bin/python3-backup"
fi

# Custom SUID binary that calls system() relying on PATH
cat > /tmp/vuln_suid.c <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char *argv[]) {
    setuid(0);
    setgid(0);
    // Intentional PATH-dependent system() call (for PATH hijack testing)
    system("id; whoami");
    return 0;
}
EOF
if command -v gcc >/dev/null 2>&1; then
    gcc /tmp/vuln_suid.c -o /usr/local/bin/vuln_suid 2>/dev/null
    chmod 4755 /usr/local/bin/vuln_suid
    rm -f /tmp/vuln_suid.c
    c_ok "SUID: /usr/local/bin/vuln_suid (PATH-dependent system call)"
else
    c_warn "gcc not found; skipping custom SUID binary"
fi

# =============================================================================
# 5. Capability (cap_setuid+ep on python3)
# =============================================================================
c_step "5. Grant cap_setuid capability to Python3"

PY3_PATH=$(readlink -f /usr/bin/python3 2>/dev/null)
if [ -n "$PY3_PATH" ] && [ -f "$PY3_PATH" ]; then
    setcap cap_setuid+ep "$PY3_PATH"
    c_ok "cap_setuid+ep: $PY3_PATH"
    c_info "Example: python3 -c 'import os; os.setuid(0); os.system(\"/bin/sh\")'"
else
    c_warn "python3 not found"
fi

# =============================================================================
# 6. World-writable cron job
# =============================================================================
c_step "6. World-writable cron script"

mkdir -p /opt/scripts
cat > /opt/scripts/backup.sh <<'EOF'
#!/bin/bash
# Daily backup script
echo "Backup started at $(date)" >> /var/log/backup.log
EOF
chmod 777 /opt/scripts/backup.sh   # world writable
chown root:root /opt/scripts/backup.sh

# Register in root's cron
cat > /etc/cron.d/vuln_backup <<EOF
# World-writable script executed as root
* * * * * root /opt/scripts/backup.sh
EOF
chmod 644 /etc/cron.d/vuln_backup
c_ok "World-writable /opt/scripts/backup.sh runs every minute as root"

# =============================================================================
# 7. Cron with relative path + writable PATH
# =============================================================================
c_step "7. Cron script using relative path + PATH hijack"

mkdir -p /opt/maintenance
cat > /opt/maintenance/cleanup.sh <<'EOF'
#!/bin/bash
# Maintenance script (relative command call = PATH hijack candidate)
cd /tmp
overlayfs_check                    # resolved via PATH (first match wins)
date >> /var/log/cleanup.log
EOF
chmod 755 /opt/maintenance/cleanup.sh
chown root:root /opt/maintenance/cleanup.sh

# Run via cron with a writable directory at the front of PATH
mkdir -p /opt/custom_bin
chmod 777 /opt/custom_bin

cat > /etc/cron.d/vuln_maintenance <<EOF
# PATH hijack cron job (writable directory is first in PATH)
PATH=/opt/custom_bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
* * * * * root /opt/maintenance/cleanup.sh
EOF
chmod 644 /etc/cron.d/vuln_maintenance
c_ok "Cron: /opt/maintenance/cleanup.sh calls overlayfs_check with relative path"
c_ok "PATH prefix: /opt/custom_bin (chmod 777)"
c_info "Example: drop a shell script at /opt/custom_bin/overlayfs_check"

# =============================================================================
# 8. Cron wildcard tar injection
# =============================================================================
c_step "8. Cron wildcard tar (option-named file privilege escalation)"

mkdir -p /opt/backups /var/backup_target
chmod 777 /var/backup_target   # writable source directory

cat > /opt/backups/archive.sh <<'EOF'
#!/bin/bash
# Backup via wildcard expansion (filenames can become tar options)
cd /var/backup_target
tar cf /opt/backups/backup.tar *
EOF
chmod 755 /opt/backups/archive.sh
chown root:root /opt/backups/archive.sh

cat > /etc/cron.d/vuln_archive <<EOF
# Wildcard tar attack target
*/2 * * * * root /opt/backups/archive.sh
EOF
chmod 644 /etc/cron.d/vuln_archive
c_ok "Cron: tar cf ... * (wildcard) executed as root every 2 minutes"
c_info "Example: place the following in /var/backup_target"
c_info "  touch -- '--checkpoint=1'"
c_info "  touch -- '--checkpoint-action=exec=sh payload.sh'"
c_info "  drop payload.sh with your commands, chmod +x"

# =============================================================================
# 9. /etc/passwd writable, /etc/shadow readable
# =============================================================================
c_step "9. Make /etc/passwd writable and /etc/shadow readable"

chmod 666 /etc/passwd
c_ok "chmod 666 /etc/passwd (world writable -> can add UID 0 user)"

chmod 644 /etc/shadow
c_ok "chmod 644 /etc/shadow (world readable -> hash extraction + cracking)"

c_info "Example:"
c_info "  echo 'attacker::0:0:root:/root:/bin/bash' >> /etc/passwd"
c_info "  su attacker  (UID 0 without password)"

# =============================================================================
# 10. Credentials in .bash_history
# =============================================================================
c_step "10. Plant credentials in .bash_history"

cat > "$LOWHOME/.bash_history" <<'EOF'
ls -la
cd /opt
./deploy.sh
mysql -u dbadmin -p'DBadm1n!P@ss2024' -h db.internal
ssh backup@192.168.100.50
# password above: B@ckupSrv!2024
export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
curl -u admin:AdminP@ss2024 https://api.internal/v1/status
sudo -i
# root password hint: R00tP@ssw0rd!
exit
history
EOF
chown "$LOWUSER:$LOWUSER" "$LOWHOME/.bash_history"
chmod 600 "$LOWHOME/.bash_history"
c_ok "Planted DB, SSH, AWS, API, and root credentials in .bash_history"

# =============================================================================
# 11. Root SSH private key inside lowuser's ~/.ssh
# =============================================================================
c_step "11. Place root's SSH private key inside lowuser's ~/.ssh"

# Prepare root's .ssh
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Prepare lowuser's .ssh
mkdir -p "$LOWHOME/.ssh"
chown "$LOWUSER:$LOWUSER" "$LOWHOME/.ssh"
chmod 700 "$LOWHOME/.ssh"

# Generate a key pair with no passphrase (lab only)
ssh-keygen -t ed25519 -f /tmp/root_key -N "" -C "root@$(hostname)" -q

# Register public key in root's authorized_keys
cat /tmp/root_key.pub >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Place private key inside lowuser's .ssh ("why is this here?" scenario)
cp /tmp/root_key "$LOWHOME/.ssh/id_rsa_root_backup"
chown "$LOWUSER:$LOWUSER" "$LOWHOME/.ssh/id_rsa_root_backup"
chmod 600 "$LOWHOME/.ssh/id_rsa_root_backup"

# Leave a suggestive README
cat > "$LOWHOME/.ssh/README.txt" <<EOF
# Stashed root's key here temporarily during maintenance.
# Usage: ssh -i ~/.ssh/id_rsa_root_backup root@localhost
EOF
chown "$LOWUSER:$LOWUSER" "$LOWHOME/.ssh/README.txt"

# Cleanup temp files
rm -f /tmp/root_key /tmp/root_key.pub

# Allow root login on sshd
if [ -f /etc/ssh/sshd_config ]; then
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    c_ok "sshd: PermitRootLogin yes"
fi

c_ok "Placed ~/.ssh/id_rsa_root_backup (root SSH key)"

# =============================================================================
# 12. /root/.ssh/authorized_keys writable
# =============================================================================
c_step "12. Make /root/.ssh/authorized_keys world writable"

chmod 777 /root/.ssh
chmod 666 /root/.ssh/authorized_keys
c_ok "chmod 777 /root/.ssh, chmod 666 /root/.ssh/authorized_keys"
c_info "Example: append your public key and ssh root@host"

# =============================================================================
# 13. LD_PRELOAD (sudoers env_keep)
# =============================================================================
c_step "13. Preserve LD_PRELOAD across sudo"

cat > /etc/sudoers.d/vuln_envkeep <<EOF
# Keep LD_PRELOAD / LD_LIBRARY_PATH across sudo
Defaults env_keep += "LD_PRELOAD"
Defaults env_keep += "LD_LIBRARY_PATH"
Defaults env_keep += "PYTHONPATH"
# Grant lowuser sudo on a specific command (LD_PRELOAD trigger)
$LOWUSER ALL=(root) NOPASSWD: /usr/bin/apt-get update
EOF
chmod 440 /etc/sudoers.d/vuln_envkeep
c_ok "sudoers env_keep: LD_PRELOAD / LD_LIBRARY_PATH / PYTHONPATH"
c_info "Example: build a malicious .so, then LD_PRELOAD=/tmp/evil.so sudo apt-get update"

# =============================================================================
# 14. Add lowuser to the docker group
# =============================================================================
c_step "14. Add lowuser to the docker group"

if getent group docker >/dev/null; then
    usermod -aG docker "$LOWUSER"
    c_ok "$LOWUSER added to docker group"
    # Check for docker command
    if command -v docker >/dev/null 2>&1; then
        systemctl enable --now docker 2>/dev/null
        # Pre-pull a common image (useful for offline labs)
        docker pull alpine:latest 2>/dev/null && c_ok "Pulled alpine:latest"
    else
        c_warn "docker command missing; install with: apt install docker.io"
    fi
    c_info "Example: docker run -v /:/host -it alpine chroot /host /bin/bash"
else
    c_warn "docker group not found; install docker.io"
fi

# =============================================================================
# 15. Summary
# =============================================================================
c_step "Setup summary"

cat <<SUMMARY

=== Lab setup complete ===

[Credentials]
  Low-privileged user: $LOWUSER / $LOWPASS
  Root password: $ROOTPASS_FOR_LAB (known, lab only)

[Injected vulnerabilities]
  1.  Created user lowuser
  2.  sudo NOPASSWD: find, less, vim, awk, env (GTFOBins)
  3.  sudo cat /var/log/*.log (wildcard path traversal)
  4.  SUID: find, less, nmap, python3-backup, vuln_suid
  5.  Capability: python3 cap_setuid+ep
  6.  World-writable cron script: /opt/scripts/backup.sh
  7.  Cron with relative path: /opt/maintenance/cleanup.sh + PATH=/opt/custom_bin
  8.  Cron wildcard tar: /opt/backups/archive.sh
  9.  /etc/passwd (666) / /etc/shadow (644)
  10. .bash_history with DB/SSH/AWS/API credentials
  11. ~/.ssh/id_rsa_root_backup (root SSH key)
  12. /root/.ssh/authorized_keys (666, writable)
  13. sudoers env_keep: LD_PRELOAD / LD_LIBRARY_PATH / PYTHONPATH
  14. lowuser added to docker group

SUMMARY

c_ok "All done."
