#!/bin/bash
#---------------------------------------------
#+++++++++++++++++++++++++++++++++++++++++++++
#+++++++   SNC PCE HOST PREPARATION   ++++++++
#+++++++++++++++++++++++++++++++++++++++++++++
#---------------------------------------------

#+++++++++++++++++++++++++++++++++++++++++++++
#++++  DISABLE ROOT SSH LOGIN (OPTIONAL)  ++++
#++++   UNCOMMENT LINES BELOW TO ENABLE   ++++
#+++++++++++++++++++++++++++++++++++++++++++++

#directory="/etc/ssh/sshd_config.d/"
#exclude_patterns=("*.conf.bak" "*.conf.old")

#exclude_options=()
#for pattern in "${exclude_patterns[@]}"; do
#  exclude_options+=("--exclude=$pattern")
#done

#files_with_permit_root_login=$(sudo grep -rl "${exclude_options[@]}" "PermitRootLogin yes" $directory)

#if [ -n "$files_with_permit_root_login" ]; then
#  echo "Files with 'PermitRootLogin yes' found:"
#  echo "$files_with_permit_root_login"

#  # Replace the line "PermitRootLogin yes" with "PermitRootLogin no" in each file
#  sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' $files_with_permit_root_login
#  echo "Root login is now disabled for SSH"
#else
#  echo "No files with 'PermitRootLogin yes' found in $directory"
#fi

#+++++++++++++++++++++++++++++++++++++++++++++
#++++++++ DISABLE SE LINUX (OPTIONAL) ++++++++
#++++   UNCOMMENT LINES BELOW TO ENABLE   ++++
#+++++++++++++++++++++++++++++++++++++++++++++

#sudo setenforce 0
#sudo sed -i --follow-symlinks 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config

#+++++++++++++++++++++++++++++++++++++++++++++
#+++++++++ UPDATE & INSTALL PACKAGES +++++++++
#+++++++++++++++++++++++++++++++++++++++++++++

echo "Updating packages..."
sudo dnf update -y
echo "dnf update complete!"

echo "Downloading packages to support PCE"
sudo dnf install -y bzip2 chkconfig initscripts bind-utils openssh-clients patch traceroute tcpdump ipset postfix logrotate ca-certificates procps-ng util-linux net-tools epel-release
echo "dnf install complete!"

#+++++++++++++++++++++++++++++++++++++++++++++
#+++++++ MODIFY PROCESS & FILE LIMITS ++++++++
#+++++++++++++++++++++++++++++++++++++++++++++

directory="/etc/systemd/system/illumio-pce.service.d/"
if [ ! -d "$directory" ]; then
  echo "$directory doesn't exist, creating..."
  sudo mkdir /etc/systemd/system/illumio-pce.service.d/
else
  echo "$directory exists..."
fi
sudo cat <<EOF | sudo tee /etc/systemd/system/illumio-pce.service.d/override.conf > /dev/null 2>&1
[Service]
LimitCORE=0
LimitNOFILE=65535
LimitNPROC=65535
EOF

sudo systemctl daemon-reload > /dev/null 2>&1

echo "Modified Process Limits at /etc/systemd/system/illumio-pce.service.d/override.conf"

sudo cat <<EOF | sudo tee /etc/sysctl.d/99-illumio.conf > /dev/null 2>&1
fs.file-max          = 2000000
vm.overcommit_memory = 1
net.core.somaxconn   = 16384
EOF

sysctl -p /etc/sysctl.d/99-illumio.conf > /dev/null 2>&1
echo "Modified File Limits at /etc/sysctl.d/99-illumio.conf"
