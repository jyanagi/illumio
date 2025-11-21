#
# This script is used to configure and mount three (3) additional
# disks as logical volumes to support the Illumio Platform for
# datacenter (on-prem) deployments.
#
# For example, a VM template is used to deploy a minimal CentOS VM. 
# Three additional hard disks are added to this VM deployment and 
# must be configured.
#
# Three (3) partitions are created: /var/log, /var/lib/illumio-pce,
# and /var/lib/illumio-pce/data/Explorer
#
# Because /var/log is already configured in the filesystem, the
# script creates a new mountpoint /mnt/new_varlog, resyncs all files
# within the /var/log directory and remounts to avoid any loss of
# logging data.
#

#!/usr/bin/env bash
set -euo pipefail

# --- Disk / LV / Mount Configuration ---
DISK_VARLOG="/dev/sdb"
VG_VARLOG="vg_varlog"
LV_VARLOG="lv_varlog"
MP_VARLOG="/var/log"
TEMP_MP_VARLOG="/mnt/new_varlog"
LV_VARLOG_PATH="/dev/${VG_VARLOG}/${LV_VARLOG}"

DISK_PCE="/dev/sdc"
VG_PCE="vg_pce"
LV_PCE="lv_pce"
MP_PCE="/var/lib/illumio-pce"
LV_PCE_PATH="/dev/${VG_PCE}/${LV_PCE}"

DISK_PCE_EXPLORER="/dev/sdd"
VG_PCE_EXPLORER="vg_pce_explorer"
LV_PCE_EXPLORER="lv_pce_explorer"
MP_PCE_EXPLORER="/var/lib/illumio-pce/data/Explorer"
LV_PCE_EXPLORER_PATH="/dev/${VG_PCE_EXPLORER}/${LV_PCE_EXPLORER}"

LOG_SERVICES=("rsyslog" "systemd-journald")

# --- Helpers: Privilege and dependency checks ---
require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "This script must be run as root." >&2
    exit 1
  fi
}

require_cmds() {
  local CMDS=("parted" "pvcreate" "vgcreate" "lvcreate" "mkfs.xfs" "rsync" "blkid" "lsblk" "systemctl" "pvs" "vgdisplay" "lvdisplay" "partprobe")
  for c in "${CMDS[@]}"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      echo "Required command '$c' not found. Please install it and rerun." >&2
      exit 1
    fi
  done
}

# --- Helpers: Disk partitioning and LVM setup ---
partition_disk_if_needed() {
  local dev="$1"
  local part="${dev}1"

  if [[ ! -b "$dev" ]]; then
    echo "ERROR: Disk $dev does not exist." >&2
    exit 1
  fi

  if lsblk -no NAME "$dev" | grep -q "^${dev##*/}1$"; then
    echo "Partition $part already exists on $dev, skipping partitioning."
  else
    echo "Partitioning $dev..."
    parted "$dev" --script mklabel gpt mkpart primary 0% 100%
    partprobe "$dev" || true
  fi

  if [[ ! -b "$part" ]]; then
    echo "ERROR: Partition $part was not created successfully." >&2
    exit 1
  fi
}

ensure_pv() {
  local part="$1"
  if pvs "$part" >/dev/null 2>&1; then
    echo "Physical volume $part already exists."
  else
    echo "Creating PV on $part..."
    pvcreate -ff -y "$part"
  fi
}

ensure_vg() {
  local vg="$1"
  local part="$2"
  if vgdisplay "$vg" >/dev/null 2>&1; then
    echo "Volume group $vg already exists."
  else
    echo "Creating VG $vg on $part..."
    vgcreate "$vg" "$part"
  fi
}

ensure_lv() {
  local vg="$1"
  local lv="$2"
  if lvdisplay "/dev/${vg}/${lv}" >/dev/null 2>&1; then
    echo "Logical volume /dev/${vg}/${lv} already exists."
  else
    echo "Creating LV $lv in $vg..."
    lvcreate -l 100%FREE -n "$lv" "$vg"
  fi
}

ensure_xfs_fs() {
  local devpath="$1"
  local fstype

  fstype=$(blkid -o value -s TYPE "$devpath" || true)
  if [[ -n "$fstype" && "$fstype" != "xfs" ]]; then
    echo "ERROR: $devpath already has filesystem type '$fstype'. Aborting." >&2
    exit 1
  fi

  if [[ "$fstype" == "xfs" ]]; then
    echo "Filesystem already exists on $devpath (xfs), skipping mkfs."
  else
    echo "Creating XFS filesystem on $devpath..."
    mkfs.xfs -f "$devpath"
  fi
}

# --- Helpers: fstab and services ---
add_fstab_entry() {
  local devpath="$1"
  local mountpoint="$2"

  local uuid
  uuid=$(blkid -s UUID -o value "$devpath")
  if [[ -z "$uuid" ]]; then
    echo "ERROR: Could not get UUID for $devpath" >&2
    exit 1
  fi

  if grep -qE "[[:space:]]${mountpoint}[[:space:]]" /etc/fstab; then
    echo "fstab entry for ${mountpoint} already exists, skipping."
    return
  fi

  echo "Adding fstab entry for ${mountpoint}..."
  cat <<EOF >> /etc/fstab
UUID=${uuid}  ${mountpoint}  xfs  defaults  0 0
EOF
}

stop_log_services() {
  echo "Stopping logging services..."
  for svc in "${LOG_SERVICES[@]}"; do
    if systemctl is-active --quiet "$svc"; then
      systemctl stop "$svc"
    fi
  done
}

start_log_services() {
  echo "Starting logging services..."
  for svc in "${LOG_SERVICES[@]}"; do
    if systemctl is-enabled --quiet "$svc"; then
      systemctl start "$svc" || true
    fi
  done
}

# --- LVM setup for a disk / VG / LV triple (no output capture) ---
setup_lvm_for() {
  local disk="$1"
  local vg="$2"
  local lv="$3"
  local lvpath="$4"

  partition_disk_if_needed "$disk"
  local part="${disk}1"

  ensure_pv "$part"
  ensure_vg "$vg" "$part"
  ensure_lv "$vg" "$lv"
  ensure_xfs_fs "$lvpath"
}

# --- Step 1: /var/log migration using a temporary mount ---
setup_varlog() {
  echo "=== Setting up LVM for /var/log ==="

  setup_lvm_for "$DISK_VARLOG" "$VG_VARLOG" "$LV_VARLOG" "$LV_VARLOG_PATH"

  mkdir -p "$TEMP_MP_VARLOG"

  stop_log_services

  echo "Mounting $LV_VARLOG_PATH on $TEMP_MP_VARLOG for migration..."
  mount "$LV_VARLOG_PATH" "$TEMP_MP_VARLOG"

  echo "Migrating /var/log data..."
  rsync -aHAX /var/log/ "$TEMP_MP_VARLOG"/

  echo "Unmounting temporary mount..."
  umount "$TEMP_MP_VARLOG"

  if [[ -e "$MP_VARLOG.old" ]]; then
    echo "Backup $MP_VARLOG.old already exists, skipping rename."
  else
    echo "Backing up original /var/log to /var/log.old..."
    mv "$MP_VARLOG" "$MP_VARLOG.old"
  fi

  mkdir -p "$MP_VARLOG"

  add_fstab_entry "$LV_VARLOG_PATH" "$MP_VARLOG"

  mount "$MP_VARLOG"

  start_log_services
}

# --- Step 2: Simple replacement mounts for PCE and Explorer ---
setup_simple_mount() {
  local disk="$1"
  local vg="$2"
  local lv="$3"
  local mp="$4"
  local lvpath="$5"

  echo "=== Setting up LVM for ${mp} ==="

  setup_lvm_for "$disk" "$vg" "$lv" "$lvpath"

  if [[ -d "$mp" && ! -L "$mp" ]]; then
    if [[ -e "${mp}.old" ]]; then
      echo "Backup ${mp}.old already exists, skipping rename."
    else
      echo "Backing up existing ${mp} to ${mp}.old"
      mv "$mp" "${mp}.old"
    fi
  fi

  mkdir -p "$mp"

  add_fstab_entry "$lvpath" "$mp"

  mount "$mp"
}

# --- Main execution flow ---
require_root
require_cmds

setup_varlog
setup_simple_mount "$DISK_PCE" "$VG_PCE" "$LV_PCE" "$MP_PCE" "$LV_PCE_PATH"
setup_simple_mount "$DISK_PCE_EXPLORER" "$VG_PCE_EXPLORER" "$LV_PCE_EXPLORER" "$MP_PCE_EXPLORER" "$LV_PCE_EXPLORER_PATH"

echo "=== Final State ==="
lsblk
echo
mount | grep -E "/var/log|/var/lib/illumio-pce" || true

cat <<EOF

All done.

Configured:
  - $DISK_VARLOG -> $VG_VARLOG/$LV_VARLOG -> $MP_VARLOG
  - $DISK_PCE -> $VG_PCE/$LV_PCE -> $MP_PCE
  - $DISK_PCE_EXPLORER -> $VG_PCE_EXPLORER/$LV_PCE_EXPLORER -> $MP_PCE_EXPLORER

Backups created (if originals existed):
  - /var/log.old
  - /var/lib/illumio-pce.old
  - /var/lib/illumio-pce/data/Explorer.old

Verify mounts and contents before deleting backups.

EOF
