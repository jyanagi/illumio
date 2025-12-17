#!/usr/bin/env bash
set -euo pipefail

# --- Globals (edit these) ---

# Where files will be downloaded
DOWNLOAD_DIR="${DOWNLOAD_DIR:-/tmp}"

# Repository browse/index page (HTML) used to discover filenames
BROWSE_URL="${BROWSE_URL:-https://nexus.de.mo/service/rest/repository/browse/illumio/}"

# Base URL used to download actual artifacts
REPO_BASE="${REPO_BASE:-https://nexus.de.mo/repository/illumio}"

# Optional curl options (as an array; safe with set -u)
# Example to trust a private CA file:
#   CURL_OPTS+=(--cacert /etc/pki/ca-trust/source/anchors/private-ca.crt)
CURL_OPTS+=(--insecure)

# --- Globals (Do not Modify) ---

PRIVATE_CA_CONFIGURED=false
SERVER_CERT_CONFIGURED=false

# --- Helper Functions ---

die() { 
  echo "ERROR: $*" >&2; 
  exit 1; 
}

require_root() {
  if [[ ${EUID:-999} -ne 0 ]]; then
    die "This script must be run as root (sudo)."
  fi
}

check_supported_os() {
  [[ -f /etc/os-release ]] || die "Unable to determine OS version (missing /etc/os-release)."

  # shellcheck disable=SC1091
  . /etc/os-release

  local os_id="${ID,,}"
  local ver="${VERSION_ID%%.*}"  # major version only
  local kernel
  kernel="$(uname -r)"

  # Oracle Linux special handling: only RHCK (reject UEK)
  if [[ "$os_id" == "ol" || "$os_id" == "oraclelinux" ]]; then
    if [[ "$kernel" == *"uek"* ]]; then
      die "Oracle Linux detected, but system is running UEK kernel: $kernel. 
This script only supports the Red Hat Compatible Kernel (RHCK) on Oracle Linux 8/9."
    fi
    case "$ver" in
      8) echo "Detected: Oracle Linux 8 (RHCK)"; return 0 ;;
      9) echo "Detected: Oracle Linux 9 (RHCK)"; return 0 ;;
      *) die "Unsupported Oracle Linux version: $VERSION_ID" ;;
    esac
  fi

  # Treat CentOS Stream as centos:8/9 in most installs (ID is usually "centos")
  case "$os_id:$ver" in
    rhel:8)   echo "Detected: Red Hat Enterprise Linux 8" ;;
    rhel:9)   echo "Detected: Red Hat Enterprise Linux 9" ;;
    centos:8) echo "Detected: CentOS 8 (likely Stream)" ;;
    centos:9) echo "Detected: CentOS 9 (likely Stream)" ;;
    centos_stream:8|centos-stream:8) echo "Detected: CentOS Stream 8" ;;
    centos_stream:9|centos-stream:9) echo "Detected: CentOS Stream 9" ;;
    *) die "Unsupported OS detected.
This script supports only:
  - RHEL 8/9
  - CentOS 8/9 (incl. Stream)
  - Oracle Linux 8/9 (RHCK only)

Detected:
  ID=$os_id
  VERSION_ID=$VERSION_ID
  Kernel=$kernel"
      ;;
  esac
}

# --- Configure Hostname ---

set_system_hostname() {
  # Fix for terminals that display ^H instead of deleting characters
  stty erase ^H 2>/dev/null || true
  stty erase ^? 2>/dev/null || true

  while true; do
    read -rp "Enter the hostname for this Illumio Node (e.g., snc0.your.domain): " NODE_NAME

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

# --- Illumio Process and File Limits ---

set_process_limits() {
  echo ">> Applying process limits..."

  mkdir -p /etc/systemd/system/illumio-pce.service.d/

  cat > /etc/systemd/system/illumio-pce.service.d/override.conf <<'EOF'
[Service]
LimitCORE=0
LimitNOFILE=65535
LimitNPROC=65535
EOF

  systemctl daemon-reload >/dev/null 2>&1 || true
}

set_sysctl() {
  echo ">> Applying sysctl parameters..."

  cat > /etc/sysctl.d/99-illumio.conf <<'EOF'
fs.file-max = 2000000
net.core.somaxconn = 16384
vm.overcommit_memory = 1
EOF

  sysctl -p /etc/sysctl.d/99-illumio.conf >/dev/null 2>&1 || true
}

set_conntrack() {
  echo ">> Configuring nf_conntrack hashsize"

  modprobe nf_conntrack || true

  if [[ -w /sys/module/nf_conntrack/parameters/hashsize ]]; then
    echo 262144 > /sys/module/nf_conntrack/parameters/hashsize
  else
    echo "Warning: /sys/module/nf_conntrack/parameters/hashsize not writable; skipping runtime hashsize set." >&2
  fi

  cat > /etc/modprobe.d/illumio.conf <<'EOF'
options nf_conntrack hashsize=262144
EOF
}

# --- Required Packages for Illumio ---

install_required_packages() {
  echo ">> Checking for required packages..."

  local PACKAGES=(
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

  local MISSING_PKGS=()

  for pkg in "${PACKAGES[@]}"; do
    if rpm -q "$pkg" &>/dev/null; then
      echo "Already installed: $pkg"
    else
      echo "Missing: $pkg"
      MISSING_PKGS+=("$pkg")
    fi
  done

  echo

  if (( ${#MISSING_PKGS[@]} == 0 )); then
    echo "All required packages are installed."
  else
    echo "Installing missing packages:"
    printf '  %s\n' "${MISSING_PKGS[@]}"
    echo
    dnf install -y "${MISSING_PKGS[@]}"
  fi
}

# --- Disable Firewalld ---

disable_firewalld() {
  echo ">> Checking firewalld status..."

  if ! command -v firewall-cmd >/dev/null 2>&1; then
    echo "firewalld is not installed; skipping."
    return 0
  fi

  # Disable regardless (safe). If it's active, stop it too.
  if systemctl is-active --quiet firewalld; then
    systemctl disable --now firewalld
    echo "firewalld has been stopped and disabled."
  else
    systemctl disable --now firewalld >/dev/null 2>&1 || true
    echo "firewalld is not running; ensured it is disabled."
  fi
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
      tmpfile="$(mktemp)"

      local in_cert_block=0
      local seen_any_cert_end=0

      while IFS= read -r line; do
        if [[ "$line" == "-----BEGIN CERTIFICATE-----" ]]; then
          in_cert_block=1
          echo "$line" >> "$tmpfile"
          continue
        fi

        if (( in_cert_block == 0 )); then
          [[ -z "${line// }" ]] && continue
          continue
        fi

        echo "$line" >> "$tmpfile"

        if [[ "$line" == "-----END CERTIFICATE-----" ]]; then
          seen_any_cert_end=1
        fi

        if (( seen_any_cert_end == 1 )) && [[ -z "${line// }" ]]; then
          break
        fi
      done

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
      PRIVATE_CA_CONFIGURED=true

      echo
      echo "Private CA chain successfully installed and added to system trust."
      echo
      ;;
    n|no)
      echo "Private CA integration skipped."
      echo
      ;;
    *)
      echo
      echo "Invalid response. Private CA setup skipped."
      echo
      ;;
  esac
}

# --- Server Certificate and Private Key Setup ---

configure_server_certificate() {
  echo ">> Server Certificate Setup for Illumio PCE"
  echo
  read -rp "Are you configuring a server certificate and private key for this node? (Y/N): " confirm

  case "${confirm,,}" in
    y|yes)
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
      tmpcrt="$(mktemp)"

      local in_crt_block=0
      local seen_crt_end=0

      while IFS= read -r line; do
        if [[ "$line" == "-----BEGIN CERTIFICATE-----" ]]; then
          in_crt_block=1
          echo "$line" >> "$tmpcrt"
          continue
        fi

        if (( in_crt_block == 0 )); then
          [[ -z "${line// }" ]] && continue
          continue
        fi

        echo "$line" >> "$tmpcrt"

        if [[ "$line" == "-----END CERTIFICATE-----" ]]; then
          seen_crt_end=1
        fi

        if (( seen_crt_end == 1 )) && [[ -z "${line// }" ]]; then
          break
        fi
      done

      if ! grep -q "BEGIN CERTIFICATE" "$tmpcrt" || ! grep -q "END CERTIFICATE" "$tmpcrt"; then
        echo
        echo "ERROR: No valid certificate detected. Aborting."
        rm -f "$tmpcrt"
        return 1
      fi

      echo
      echo "Server certificate chain captured successfully."
      echo

      echo "Paste your SERVER PRIVATE KEY below."
      echo "Make sure the private key is not encrypted."
      echo
      echo "Recording will start at the first '-----BEGIN PRIVATE KEY-----' line"
      echo "and stop when you press Enter on a blank line after the '-----END PRIVATE KEY-----'."
      echo

      local key_path="/var/lib/illumio-pce/cert/server.key"
      local tmpkey
      tmpkey="$(mktemp)"

      local in_key_block=0
      local seen_key_end=0

      while IFS= read -r line; do
        if [[ "$line" =~ ^-----BEGIN\ .*KEY-----$ ]]; then
          in_key_block=1
          echo "$line" >> "$tmpkey"
          continue
        fi

        if (( in_key_block == 0 )); then
          [[ -z "${line// }" ]] && continue
          continue
        fi

        echo "$line" >> "$tmpkey"

        if [[ "$line" =~ ^-----END\ .*KEY-----$ ]]; then
          seen_key_end=1
        fi

        if (( seen_key_end == 1 )) && [[ -z "${line// }" ]]; then
          break
        fi
      done

      if ! grep -q "BEGIN" "$tmpkey" || ! grep -q "KEY" "$tmpkey"; then
        echo
        echo "ERROR: No valid private key detected. Aborting."
        rm -f "$tmpcrt" "$tmpkey"
        return 1
      fi

      echo
      echo "Private key captured successfully."
      echo

      echo "Installing certificate and key to:"
      echo "  $crt_path"
      echo "  $key_path"
      mkdir -p /var/lib/illumio-pce/cert/

      cp "$tmpcrt" "$crt_path"
      cp "$tmpkey" "$key_path"
      rm -f "$tmpcrt" "$tmpkey"

      chmod 400 "$crt_path" "$key_path"
      SERVER_CERT_CONFIGURED=true
      echo "Permissions set to 400 on both files."
      echo
      echo "Server certificate and private key successfully installed."
      echo
      ;;
    n|no)
      echo "Server certificate/key setup skipped."
      echo
      ;;
    *)
      echo
      echo "Invalid response. Skipping server certificate setup."
      echo
      ;;
  esac
}

# --- Illumio Binaries Download ---

fetch_index() {
  echo "Fetching repository index from:"
  echo "  ${BROWSE_URL}"
  curl -fsSL "${CURL_OPTS[@]}" "${BROWSE_URL}" || die "Failed to fetch repository index."
}

extract_filenames() {
  sed -n 's/.*href="\([^"]*\)".*/\1/p' \
    | sed -E 's@.*/@@' \
    | grep '^illumio-' \
    || true
}

find_latest() {
  local pattern="$1"
  printf '%s\n' "${FILENAMES[@]}" \
    | grep -E "${pattern}" \
    | sort -V \
    | tail -n 1 \
    || true
}

download_file() {
  local filename="$1"
  [[ -n "$filename" ]] || die "download_file(): no filename provided"

  local url="${REPO_BASE%/}/${filename}"
  local dest="${DOWNLOAD_DIR%/}/${filename}"

  echo "Downloading:"
  echo "  ${url}"
  echo "  -> ${dest}"

  curl -fSL "${CURL_OPTS[@]}" "${url}" -o "${dest}" \
    || die "Failed to download ${filename}"
}

download_binaries() {
  # shellcheck disable=SC1091
  . /etc/os-release
  local os_id="${ID,,}"
  local ver="${VERSION_ID%%.*}"
  local pce_major=""

  case "${os_id}:${ver}" in
    rhel:8|centos:8|centos_stream:8|centos-stream:8|ol:8|oraclelinux:8) pce_major="el8" ;;
    rhel:9|centos:9|centos_stream:9|centos-stream:9|ol:9|oraclelinux:9) pce_major="el9" ;;
    *) die "Unexpected OS combination (${os_id}:${ver})" ;;
  esac

  echo "Will select illumio-pce package for ${pce_major}"

  local index_html
  index_html="$(fetch_index)"

  mapfile -t FILENAMES < <(echo "${index_html}" | extract_filenames)

  (( ${#FILENAMES[@]} > 0 )) || die "No illumio* files found in repo."

  echo "Found files:"
  printf '  %s\n' "${FILENAMES[@]}"
  echo

  local PCE_PATTERN="^illumio-pce-.*\.${pce_major}\.x86_64\.rpm$"
  local PCE_UI_PATTERN="^illumio-pce-ui-.*\.x86_64\.rpm$"
  local REL_COMP_PATTERN="^illumio-release-compatibility-.*\.tar\.bz2$"
  local VEN_BUNDLE_PATTERN="^illumio-ven-bundle-.*\.tar\.bz2$"
  local VEN_PKGS_PATTERN="^illumio-ven-pkgs-.*\.tgz$"

  local pce_rpm pce_ui_rpm rel_comp ven_bundle ven_pkgs
  pce_rpm="$(find_latest "${PCE_PATTERN}")"
  pce_ui_rpm="$(find_latest "${PCE_UI_PATTERN}")"
  rel_comp="$(find_latest "${REL_COMP_PATTERN}")"
  ven_bundle="$(find_latest "${VEN_BUNDLE_PATTERN}")"
  ven_pkgs="$(find_latest "${VEN_PKGS_PATTERN}")"

  [[ -n "${pce_rpm}" ]]    || die "Missing illumio-pce"
  [[ -n "${pce_ui_rpm}" ]] || die "Missing illumio-pce-ui"
  [[ -n "${rel_comp}" ]]   || die "Missing release compatibility tarball"
  [[ -n "${ven_bundle}" ]] || die "Missing VEN bundle"
  [[ -n "${ven_pkgs}" ]]   || die "Missing VEN pkgs archive"

  echo "Selected:"
  echo "  PCE RPM        : ${pce_rpm}"
  echo "  PCE UI RPM     : ${pce_ui_rpm}"
  echo "  Release compat : ${rel_comp}"
  echo "  VEN bundle     : ${ven_bundle}"
  echo "  VEN pkgs       : ${ven_pkgs}"
  echo

  mkdir -p "${DOWNLOAD_DIR}"

  download_file "${pce_rpm}"
  download_file "${pce_ui_rpm}"
  download_file "${rel_comp}"
  download_file "${ven_bundle}"
  download_file "${ven_pkgs}"

  echo
  echo "Downloaded:"
  ls -lh "${DOWNLOAD_DIR%/}"/illumio-* 2>/dev/null || true
}

# --- PCE Installation ---

prompt_password_confirm() {
  local prompt1="${1:-Enter password: }"
  local prompt2="${2:-Confirm password: }"
  local max_tries="${3:-3}"

  local p1="" p2="" tries=1

  while (( tries <= max_tries )); do
    read -rsp "$prompt1" p1; echo
    read -rsp "$prompt2" p2; echo

    if [[ -z "$p1" ]]; then
      echo "Password cannot be empty. Try again. ($tries/$max_tries)" >&2
    elif [[ "$p1" != "$p2" ]]; then
      echo "Passwords do not match. Try again. ($tries/$max_tries)" >&2
    else
      PASSWORD="$p1"
      return 0
    fi

    ((tries++))
  done

  echo "Failed to confirm password after $max_tries attempts." >&2
  return 1
}

install_pce() {
  local USERNAME=""
  local PASSWORD=""

  wait_for_runtime() {
    local timeout="${1:-900}"
    local interval="${2:-5}"

    local start_ts now elapsed out

    echo "Waiting for Illumio Runtime to reach RUNNING state..."
    start_ts="$(date +%s)"

    while true; do
        # Capture BOTH stdout+stderr
        out="$(sudo -u ilo-pce /opt/illumio-pce/illumio-pce-ctl status 2>&1 || true)"

        # Match semantic keywords, not spacing
        if grep -qE 'Checking Illumio Runtime.*RUNNING' <<<"$out"; then
        echo "Illumio Runtime is RUNNING"
        return 0
        fi

        now="$(date +%s)"
        elapsed=$(( now - start_ts ))
        if (( elapsed >= timeout )); then
        echo "ERROR: Timed out after ${timeout}s waiting for RUNNING." >&2
        echo "Last status output was:" >&2
        echo "$out" >&2
        return 1
        fi

        sleep "$interval"
    done
  }

  read -rp "Enter Illumio PCE username (i.e., admin@illumio.com): " USERNAME
  prompt_password_confirm "Enter Illumio PCE password: " "Confirm Illumio PCE password: " 3

  # Install Illumio RPMs (from DOWNLOAD_DIR)
  rpm -Uvh "${DOWNLOAD_DIR%/}"/illumio-pce-*.rpm
  rpm -Uvh "${DOWNLOAD_DIR%/}"/illumio-pce-ui-*.rpm || true

  # Change owner and permissions for server certificate and private key (if present)
  if compgen -G "/var/lib/illumio-pce/cert/server.*" >/dev/null; then
    chown ilo-pce: /var/lib/illumio-pce/cert/server.* || true
    chmod 400 /var/lib/illumio-pce/cert/server.* || true
  fi

  # Setup PCE

  if [[ "${PRIVATE_CA_CONFIGURED}" != "true" && "${SERVER_CERT_CONFIGURED}" != "true" ]]; then
    echo ">> Illumio Setup: no Private CA and no Server Certificate/Key provided. Issuing Self-Signed certificate."
    /opt/illumio-pce/illumio-pce-env setup --generate-cert --batch \
      node_type="snc0" \
      email_address="noreply@illumio.com" \
      pce_fqdn="$(hostname)" \
      metrics_collection_enabled=false \
      expose_user_invitation_link=true \
      node_under_specs_notification_enabled=false \
      front_end_https_port=8443 \
      front_end_event_service_port=8444
    cp /var/lib/illumio-pce/cert/server.crt /etc/pki/ca-trust/source/anchors/.
    update-ca-trust
  else
    echo ">> Illumio Setup: Using provided Private CA and Server Certificate/Key."
    /opt/illumio-pce/illumio-pce-env setup --batch \
      node_type="snc0" \
      email_address="noreply@illumio.com" \
      pce_fqdn="$(hostname)" \
      metrics_collection_enabled=false \
      expose_user_invitation_link=true \
      node_under_specs_notification_enabled=false \
      front_end_https_port=8443 \
      front_end_event_service_port=8444
  fi
  
  echo "Starting PCE at Runtime Level 1"
  sudo -u ilo-pce /opt/illumio-pce/illumio-pce-ctl start --runlevel 1 &>/dev/null

  wait_for_runtime 300 5
  echo "Illumio PCE is now at Runtime Level 1"

  echo "Setting up the database..."
  sudo -u ilo-pce /opt/illumio-pce/illumio-pce-db-management setup
  echo "Database setup complete!"
  
  echo "Setting the Illumio PCE to Runtime Level 5"
  sudo -u ilo-pce /opt/illumio-pce/illumio-pce-ctl set-runlevel 5 &>/dev/null

  wait_for_runtime 300 5
  echo "Illumio PCE is now at Runtime Level 5"

  echo "Creating organization and user ($USERNAME)..."

  # Create domain
  sudo --preserve-env -u ilo-pce ILO_PASSWORD="$PASSWORD" \
    /opt/illumio-pce/illumio-pce-db-management create-domain \
      --user-name "$USERNAME" \
      --full-name "admin" \
      --org-name "$(hostname)"

  echo "Illumio PCE setup complete!"

  echo "Installing VEN bundle"

  # Install VEN bundles
  local latest_ven_bundle=""
  latest_ven_bundle="$(ls -1 "${DOWNLOAD_DIR%/}"/illumio-ven-bundle-* 2>/dev/null | sort -V | tail -n 1 || true)"
  [[ -n "$latest_ven_bundle" ]] || die "No illumio-ven-bundle-* found in ${DOWNLOAD_DIR}"

  sudo -u ilo-pce /opt/illumio-pce/illumio-pce-ctl ven-software-install \
    "$latest_ven_bundle" \
    --compatibility-matrix "${DOWNLOAD_DIR%/}"/illumio-release-compatibility-* \
    --default \
    --no-prompt \
    --orgs 1

  mapfile -t ven_bundles < <(ls -1 "${DOWNLOAD_DIR%/}"/illumio-ven-bundle-* 2>/dev/null | sort -V || true)
  for bundle in "${ven_bundles[@]}"; do
    [[ "$bundle" == "$latest_ven_bundle" ]] && continue
    sudo -u ilo-pce /opt/illumio-pce/illumio-pce-ctl ven-software-install \
      "$bundle" \
      --compatibility-matrix "${DOWNLOAD_DIR%/}"/illumio-release-compatibility-* \
      --no-prompt \
      --orgs 1
  done

  echo "Illumio VEN agent bundle successfully uploaded!"
}

# --- Main ---

main() {
  require_root
  check_supported_os
  set_system_hostname
  disable_firewalld
  configure_private_ca
  configure_server_certificate

  echo ">> Meeting Illumio pre-requisites..."
  echo

  install_required_packages
  set_process_limits
  set_sysctl
  set_conntrack

  echo
  echo ">> Downloading Illumio binaries..."
  download_binaries

  echo
  echo ">> Installing Illumio PCE..."
  install_pce

  echo
  echo ">> Illumio PCE Installation complete."

  echo "Illumio has been successfully installed."
  echo 
  echo "Open a web browser and navigate to https://$(hostname):8443"
  echo "Login with the PCE user account: $USERNAME"
}

main "$@"

# Reset stty
stty sane