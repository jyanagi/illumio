#!/usr/bin/env bash
set -euo pipefail

# --- Helper Functions ---

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (sudo)." >&2
    exit 1
  fi
}

check_supported_os() {
  # Ensure /etc/os-release exists
  if [[ ! -f /etc/os-release ]]; then
    echo "ERROR: Unable to determine OS version (missing /etc/os-release)."
    exit 1
  fi

  . /etc/os-release

  local os_id="${ID,,}"
  local ver="${VERSION_ID%%.*}"  # major version only
  local kernel="$(uname -r)"

  # Oracle Linux special handling:
  # Accept only if running Red Hat Compatible Kernel (RHCK)
  if [[ "$os_id" == "ol" || "$os_id" == "oraclelinux" ]]; then
    if [[ "$kernel" == *"uek"* ]]; then
      echo "ERROR: Oracle Linux detected, but system is running UEK kernel:"
      echo "  Kernel: $kernel"
      echo
      echo "This script only supports the Red Hat Compatible Kernel (RHCK)"
      echo "on Oracle Linux 8/9."
      exit 1
    fi

    if [[ "$ver" == "8" ]]; then
      echo "Detected: Oracle Linux 8 (RHCK)"
      return
    elif [[ "$ver" == "9" ]]; then
      echo "Detected: Oracle Linux 9 (RHCK)"
      return
    else
      echo "ERROR: Unsupported Oracle Linux version: $VERSION_ID"
      exit 1
    fi
  fi

  # Normal supported distros
  case "$os_id:$ver" in
    rhel:8)
      echo "Detected: Red Hat Enterprise Linux 8"
      ;;
    rhel:9)
      echo "Detected: Red Hat Enterprise Linux 9"
      ;;
    centos:8|centos_stream:8|centos-stream:8)
      echo "Detected: CentOS Stream 8"
      ;;
    centos:9|centos_stream:9|centos-stream:9)
      echo "Detected: CentOS Stream 9"
      ;;
    *)
      echo "ERROR: Unsupported OS detected."
      echo
      echo "This script supports only:"
      echo "  - Red Hat Enterprise Linux 8"
      echo "  - Red Hat Enterprise Linux 9"
      echo "  - CentOS Stream 8"
      echo "  - CentOS Stream 9"
      echo "  - Oracle Linux 8 (RHCK only)"
      echo "  - Oracle Linux 9 (RHCK only)"
      echo
      echo "Supported OS Detected:"
      echo "  ID=$os_id"
      echo "  VERSION_ID=$VERSION_ID"
      echo "  Kernel=$kernel"
      exit 1
      ;;
  esac
}

prompt_node_type() {
  PS3=$'\n''Enter your choice (1-4): '

  local options=("core" "data0" "data1" "snc")

  echo
  echo "Select the Illumio node type:"
  echo "-------------------------------------------"

  select opt in "${options[@]}"; do
    case "$opt" in
      core)
        NODE_TYPE="core"
        break
        ;;
      data0)
        NODE_TYPE="data0"
        break
        ;;
      data1)
        NODE_TYPE="data1"
        break
        ;;
      snc)
        NODE_TYPE="snc"
        break
        ;;
      *)
        echo
        echo "Invalid selection. Please choose 1–4."
        ;;
    esac
  done

  echo
  echo "Selected: $NODE_TYPE"
  echo
}

# --- Process Limits ---

set_common_process_limits() {
  echo ">> Setting process limits (common to all node types)..."

  mkdir -p /etc/systemd/system/illumio-pce.service.d/

  cat <<EOF > /etc/systemd/system/illumio-pce.service.d/override.conf
[Service]
LimitCORE=0
LimitNOFILE=65535
LimitNPROC=65535
EOF

  systemctl daemon-reload >/dev/null 2>&1
}

# --- Sysctl: Core Node ---

apply_core_sysctl() {
  echo ">> Applying core node sysctl parameters..."

  cat <<EOF > /etc/sysctl.d/99-illumio-core.conf
fs.file-max = 2000000
net.core.somaxconn = 16384
EOF

  sysctl -p /etc/sysctl.d/99-illumio-core.conf >/dev/null 2>&1
}

configure_conntrack_core() {
  echo ">> Configuring nf_conntrack hashsize for core/SNC node..."

  modprobe nf_conntrack || true

  if [[ -w /sys/module/nf_conntrack/parameters/hashsize ]]; then
    echo 262144 > /sys/module/nf_conntrack/parameters/hashsize
  else
    echo "Warning: /sys/module/nf_conntrack/parameters/hashsize not writable; skipping runtime hashsize set." >&2
  fi

  cat <<EOF > /etc/modprobe.d/illumio.conf
options nf_conntrack hashsize=262144
EOF
}

# --- Sysctl: Data Node ---

apply_data_sysctl() {
  echo ">> Applying data node sysctl parameters..."

  cat <<EOF > /etc/sysctl.d/99-illumio-data.conf
fs.file-max = 2000000
vm.overcommit_memory = 1
EOF

  sysctl -p /etc/sysctl.d/99-illumio-data.conf >/dev/null 2>&1
}

# --- Sysctl: SNC (Single Node Cluster) ---

apply_snc_sysctl() {
  echo ">> Applying SNC (single node cluster) sysctl parameters..."

  cat <<EOF > /etc/sysctl.d/99-illumio-snc.conf
fs.file-max = 2000000
net.core.somaxconn = 16384
vm.overcommit_memory = 1
EOF

  sysctl -p /etc/sysctl.d/99-illumio-snc.conf >/dev/null 2>&1
}

# --- Packages ---

install_required_packages() {
  echo ">> Checking for required packages..."

  PACKAGES=(
    bind-utils
    bzip2
    ca-certificates
    chkconfig
    initscripts
    ipset
    logrotate
    net-tools
    openssh-clients
    patch
    postfix
    procps-ng
    tcpdump
    traceroute
    util-linux
  )

  MISSING_PKGS=()

  for pkg in "${PACKAGES[@]}"; do
    if rpm -q "$pkg" &>/dev/null; then
      echo "Already installed: $pkg"
    else
      echo "Missing: $pkg"
      MISSING_PKGS+=("$pkg")
    fi
  done

  echo

  if [ ${#MISSING_PKGS[@]} -eq 0 ]; then
    echo "All required packages are installed."
  else
    echo "Installing missing packages:"
    printf '  %s\n' "${MISSING_PKGS[@]}"
    echo
    dnf install -y "${MISSING_PKGS[@]}"
  fi
}

# --- Set System Parameters ---
set_system_hostnames() {
  while true; do
    # Prompt for hostname
    read -rp "Enter the hostname for this Illumio Node (e.g., core0.your.domain): " NODE_NAME

    # Prevent blank or whitespace-only hostname
    if [[ -z "${NODE_NAME// }" ]]; then
      echo "Hostname cannot be empty. Please try again."
      echo
      continue
    fi

    echo
    echo "You entered: $NODE_NAME"
    read -rp "Is this correct? (Y/N): " BOOL

    case "${BOOL,,}" in
      y|yes)
        echo
        echo "Setting hostname to: $NODE_NAME"
        hostnamectl set-hostname "$NODE_NAME"
        echo "Hostname successfully updated."
        echo
        break
        ;;
      n|no)
        echo
        echo "Let's try again..."
        echo
        ;;
      *)
        echo
        echo "Invalid response. Please enter Y or N."
        echo
        ;;
    esac
  done
}

# --- Create Host Records for Illumio Cluster Members ---
add_host_records() {
  # Fix for terminals that display ^H instead of deleting characters
  stty erase ^H 2>/dev/null || true

  local hosts_entries=()
  local ip name more confirm

  echo "=== Add /etc/hosts entries for core and data nodes within the Illumio Cluster ==="
  echo

  while true; do
    read -rp "Enter IP address (e.g., 10.0.0.1): " ip
    read -rp "Enter hostname (e.g., core0.your.domain): " name

    if [[ -z "${ip// }" || -z "${name// }" ]]; then
      echo "IP and hostname cannot be empty. Please try again."
      echo
      continue
    fi

    local entry="$ip $name"
    echo
    echo "You entered the following host record:"
    echo "  $entry"
    read -rp "Is this correct? (Y/N): " confirm

    case "${confirm,,}" in
      y|yes)
        hosts_entries+=("$entry")
        echo
        echo "Staged /etc/hosts entries so far:"
        printf '  %s\n' "${hosts_entries[@]}"
        echo
        ;;
      n|no)
        echo
        echo "Discarding this entry. Let's try again."
        echo
        continue
        ;;
      *)
        echo
        echo "Invalid response. Please enter Y or N."
        echo
        continue
        ;;
    esac

    read -rp "Add another host record? (Y/N): " more
    case "${more,,}" in
      y|yes)
        echo
        continue
        ;;
      n|no)
        echo
        break
        ;;
      *)
        echo
        echo "Invalid response. Assuming 'No'."
        echo
        break
        ;;
    esac
  done

  if [[ ${#hosts_entries[@]} -eq 0 ]]; then
    echo "No host records to append to /etc/hosts."
    return 0
  fi

  echo "Final staged entries that will be appended to /etc/hosts:"
  printf '  %s\n' "${hosts_entries[@]}"
  echo
  read -rp "Proceed with updating /etc/hosts? (Y/N): " confirm

  case "${confirm,,}" in
    y|yes)
      echo "Creating backup: /etc/hosts.bak"
      cp /etc/hosts /etc/hosts.bak

      {
        echo
        echo "# Illumio node host records added on $(date)"
        for entry in "${hosts_entries[@]}"; do
          echo "$entry"
        done
      } >> /etc/hosts

      echo "Entries successfully appended to /etc/hosts."
      ;;
    *)
      echo "Aborted: /etc/hosts was not modified."
      ;;
  esac
}

# --- Firewalld Configuration ---

configure_firewalld_for_illumio() {
  echo ">> Checking firewalld status..."

  # Is firewall-cmd installed?
  if ! command -v firewall-cmd >/dev/null 2>&1; then
    echo "firewalld is not installed; skipping firewall configuration."
    return 0
  fi

  # Is firewalld running?
  if ! systemctl is-active --quiet firewalld; then
    echo "firewalld service is not active; skipping firewall configuration."
    return 0
  fi

  echo "firewalld is active."

  # Determine default interface
  local default_iface
  default_iface=$(ip -4 route show default 2>/dev/null | awk '/default/ {for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1); exit}')

  if [[ -z "$default_iface" ]]; then
    echo "WARNING: Unable to determine default interface. Using default zone."
  else
    echo "Default interface detected: $default_iface"
  fi

  # Determine zone for the NIC
  local ZONE
  if [[ -n "$default_iface" ]]; then
    ZONE=$(firewall-cmd --get-active-zones | awk -v dev="$default_iface" '
      /^[a-zA-Z0-9_-]+$/ {zone=$1}
      /interfaces:/ {
        for (i=2;i<=NF;i++) {
          gsub(/,/,"",$i)
          if ($i == dev) {print zone; exit}
        }
      }')
  fi

  if [[ -z "$ZONE" ]]; then
    ZONE=$(firewall-cmd --get-default-zone)
    echo "Using default firewalld zone: $ZONE"
  else
    echo "Using firewalld zone: $ZONE"
  fi

  echo

  # Collect Illumio host IPs from /etc/hosts
  local ips=()
  mapfile -t ips < <(awk '
    /^# Illumio node host records added on / {flag=1; next}
    flag && $1 !~ /^#/ && NF >= 2 {print $1}
  ' /etc/hosts 2>/dev/null)

  if [[ ${#ips[@]} -eq 0 ]]; then
    echo "No Illumio IP entries found in /etc/hosts. Skipping IP-based rules."
  fi

  # Display proposed firewall rules
  echo "Proposed firewalld rules to be added:"
  echo

  if [[ ${#ips[@]} -gt 0 ]]; then
    for IP in "${ips[@]}"; do
      echo "  firewall-cmd --permanent --zone=\"$ZONE\" --add-rich-rule=\"rule family=\"ipv4\" source address=\"$IP\" accept\""
    done
  fi

  if [[ "$NODE_TYPE" == "core" ]]; then
    echo "  firewall-cmd --permanent --zone=\"$ZONE\" --add-port=8443/tcp"
    echo "  firewall-cmd --permanent --zone=\"$ZONE\" --add-port=8444/tcp"
  fi

  echo
  read -rp "Apply these firewall rules? (Y/N): " confirm
  echo

  case "${confirm,,}" in
    y|yes)
      echo "Applying firewalld rules..."
      ;;
    *)
      echo "Firewall configuration aborted by user."
      return 0
      ;;
  esac

  # Apply firewall rules
  if [[ ${#ips[@]} -gt 0 ]]; then
    for IP in "${ips[@]}"; do
      echo "Adding rule: allow from $IP"
      firewall-cmd --permanent --zone="$ZONE" \
        --add-rich-rule="rule family=\"ipv4\" source address=\"$IP\" accept"
    done
  fi

  if [[ "$NODE_TYPE" == "core" ]]; then
    echo "Opening core ports 8443 and 8444..."
    firewall-cmd --permanent --zone="$ZONE" --add-port=8443/tcp
    firewall-cmd --permanent --zone="$ZONE" --add-port=8444/tcp
  fi

  echo
  echo "Reloading firewalld..."
  firewall-cmd --reload
  echo "firewalld configuration completed."
}

# --- Private CA Configuration ---

configure_private_ca() {
  echo ">> Private Certificate Authority (CA) Setup"
  echo
  read -rp "Are you incorporating a private CA? (Y/N): " confirm

  case "${confirm,,}" in
    y|yes)
      echo
      echo "Paste your private CA certificate chain below."
      echo "Include all root and intermediate certificates."
      echo
      echo "Recording will start at the first '-----BEGIN CERTIFICATE-----'"
      echo "and stop when you press Enter on a blank line after the last"
      echo "'-----END CERTIFICATE-----'."
      echo

      local ca_path="/etc/pki/ca-trust/source/anchors/private-ca.crt"
      local tmpfile
      tmpfile=$(mktemp)

      local in_cert_block=0
      local seen_any_cert_end=0

      while IFS= read -r line; do
        # Start recording at the first BEGIN CERTIFICATE
        if [[ "$line" == "-----BEGIN CERTIFICATE-----" ]]; then
          in_cert_block=1
          echo "$line" >> "$tmpfile"
          continue
        fi

        # If we haven't started the cert block yet, ignore everything else
        if [[ $in_cert_block -eq 0 ]]; then
          # Allow user to paste leading blank lines without breaking things
          if [[ -z "${line// }" ]]; then
            continue
          fi
          # Ignore other text before BEGIN CERTIFICATE
          continue
        fi

        # Once in_cert_block == 1, record every line
        echo "$line" >> "$tmpfile"

        # Track when we see any END CERTIFICATE
        if [[ "$line" == "-----END CERTIFICATE-----" ]]; then
          seen_any_cert_end=1
        fi

        # If we've already seen at least one END CERTIFICATE
        # and the user now enters a blank line, we stop.
        if [[ $seen_any_cert_end -eq 1 && -z "${line// }" ]]; then
          break
        fi

      done

      # Validate content: require at least one BEGIN and one END
      if ! grep -q "BEGIN CERTIFICATE" "$tmpfile" || ! grep -q "END CERTIFICATE" "$tmpfile"; then
        echo
        echo "ERROR: No valid certificate data detected. Private CA setup aborted."
        rm -f "$tmpfile"
        return 1
      fi

      echo
      echo "Installing private CA certificate chain to:"
      echo "  $ca_path"
      mkdir -p /etc/pki/ca-trust/source/anchors/

      cp "$tmpfile" "$ca_path"
      rm -f "$tmpfile"

      echo "Updating CA trust store..."
      update-ca-trust

      echo
      echo "Private CA chain successfully installed and added to system trust."
      echo
      ;;

    n|no)
      echo "Private CA integration skipped."
      echo
      return 0
      ;;

    *)
      echo
      echo "Invalid response. Private CA setup skipped."
      echo
      return 0
      ;;
  esac
}

# --- Server Certificate Configuration (Core Nodes Only) ---

# --- Server Certificate and Private Key Setup (Core Nodes Only) ---

configure_server_certificate() {
  # Only applies to core nodes
  if [[ "${NODE_TYPE:-}" != "core" ]]; then
    echo "Server certificate configuration is only required for core nodes. Skipping."
    echo
    return 0
  fi

  echo ">> Server Certificate Setup for Illumio Core Node"
  echo
  read -rp "Are you configuring a server certificate and private key for this core node? (Y/N): " confirm

  case "${confirm,,}" in
    y|yes)
      # STEP 1: GET SERVER CERTIFICATE
      echo
      echo "Paste your SERVER CERTIFICATE CHAIN below."
      echo "Include leaf + intermediate(s) + root if applicable."
      echo
      echo "Recording will start at the first '-----BEGIN CERTIFICATE-----'"
      echo "and will stop when you press Enter on a BLANK line after the last"
      echo "'-----END CERTIFICATE-----'."
      echo

      local crt_path="/var/lib/illumio-pce/cert/server.crt"
      local tmpcrt
      tmpcrt=$(mktemp)

      local in_crt_block=0
      local seen_crt_end=0

      while IFS= read -r line; do
        if [[ "$line" == "-----BEGIN CERTIFICATE-----" ]]; then
          in_crt_block=1
          echo "$line" >> "$tmpcrt"
          continue
        fi

        if [[ $in_crt_block -eq 0 ]]; then
          [[ -z "${line// }" ]] && continue
          continue
        fi

        echo "$line" >> "$tmpcrt"

        if [[ "$line" == "-----END CERTIFICATE-----" ]]; then
          seen_crt_end=1
        fi

        if [[ $seen_crt_end -eq 1 && -z "${line// }" ]]; then
          break
        fi

      done

      # Validate certificate content
      if ! grep -q "BEGIN CERTIFICATE" "$tmpcrt" || ! grep -q "END CERTIFICATE" "$tmpcrt"; then
        echo
        echo "ERROR: No valid certificate detected. Aborting."
        rm -f "$tmpcrt"
        return 1
      fi

      echo
      echo "Server certificate chain captured successfully."
      echo

      # STEP 2: GET PRIVATE KEY

      echo "Paste your SERVER PRIVATE KEY below."
      echo "Make sure the private key is not encrypted."
      echo 
      echo "Recording will start at the first '-----BEGIN PRIVATE KEY----- ' line"
      echo "and stop at the corresponding '-----END PRIVATE KEY----- ' line and a blank line."
      echo

      local key_path="/var/lib/illumio-pce/cert/server.key"
      local tmpkey
      tmpkey=$(mktemp)

      local in_key_block=0
      local seen_key_end=0

      while IFS= read -r line; do
        # Detect BEGIN KEY line (RSA, EC, PRIVATE KEY, etc.)
        if [[ "$line" =~ ^-----BEGIN\ .*KEY-----$ ]]; then
          in_key_block=1
          echo "$line" >> "$tmpkey"
          continue
        fi

        if [[ $in_key_block -eq 0 ]]; then
          [[ -z "${line// }" ]] && continue
          continue
        fi

        echo "$line" >> "$tmpkey"

        if [[ "$line" =~ ^-----END\ .*KEY-----$ ]]; then
          seen_key_end=1
        fi

        if [[ $seen_key_end -eq 1 && -z "${line// }" ]]; then
          break
        fi

      done

      # Validate private key content
      if ! grep -q "BEGIN" "$tmpkey" || ! grep -q "KEY" "$tmpkey"; then
        echo
        echo "ERROR: No valid private key detected. Aborting."
        rm -f "$tmpcrt" "$tmpkey"
        return 1
      fi

      echo
      echo "Private key captured successfully."
      echo

      # STEP 3: INSTALL CERTIFICATE AND KEY

      echo "Installing certificate and key to:"
      echo "  $crt_path"
      echo "  $key_path"
      mkdir -p /var/lib/illumio-pce/cert/

      cp "$tmpcrt" "$crt_path"
      cp "$tmpkey" "$key_path"
      rm -f "$tmpcrt" "$tmpkey"

      chmod 400 "$crt_path"
      chmod 400 "$key_path"

      echo "Permissions set to 400 on both files."

      echo
      echo "Server certificate and private key successfully installed for the core node."
      echo
      ;;

    n|no)
      echo "Server certificate/key setup skipped."
      echo
      return 0
      ;;

    *)
      echo
      echo "Invalid response. Skipping server certificate setup."
      echo
      return 0
      ;;
  esac
}

# --- Summary ---

summarize_core() {
  echo
  echo "Configuration complete for Illumio core node."
  echo "- Process limits:      /etc/systemd/system/illumio-pce.service.d/override.conf"
  echo "- Core sysctl:         /etc/sysctl.d/99-illumio-core.conf"
  echo "- nf_conntrack config: /etc/modprobe.d/illumio.conf"
  echo "- Server certificate:  /var/lib/illumio-pce/cert/server.crt"
  echo "- Server key:          /var/lib/illumio-pce/cert/server.key"
}

summarize_data() {
  echo
  echo "Configuration complete for Illumio data node: $NODE_TYPE"
  echo "- Process limits:      /etc/systemd/system/illumio-pce.service.d/override.conf"
  echo "- Data sysctl:         /etc/sysctl.d/99-illumio-data.conf"
}

summarize_snc() {
  echo
  echo "Configuration complete for Illumio SNC (single node cluster)."
  echo "- Process limits:      /etc/systemd/system/illumio-pce.service.d/override.conf"
  echo "- SNC sysctl:          /etc/sysctl.d/99-illumio-snc.conf"
  echo "- nf_conntrack config: /etc/modprobe.d/illumio.conf"
}

# --- Main ---

main() {
  require_root
  check_supported_os
  set_system_hostnames
  add_host_records
  prompt_node_type
  configure_firewalld_for_illumio
  configure_private_ca
  configure_server_certificate

  echo "Configuring Illumio PCE settings for node type: $NODE_TYPE"
  echo

  install_required_packages
  set_common_process_limits

  case "$NODE_TYPE" in
    core)
      apply_core_sysctl
      configure_conntrack_core
      summarize_core
      ;;
    snc)
      apply_snc_sysctl
      configure_conntrack_core
      summarize_snc
      ;;
    data0|data1)
      apply_data_sysctl
      summarize_data
      ;;
  esac
}

main "$@"
