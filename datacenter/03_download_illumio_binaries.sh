#!/usr/bin/env bash
set -euo pipefail

# --- OS Detection ---
check_supported_os() {
  # Ensure /etc/os-release exists
  if [[ ! -f /etc/os-release ]]; then
    echo "ERROR: Unable to determine OS version (missing /etc/os-release)."
    exit 1
  fi

  . /etc/os-release

  local os_id="${ID,,}"
  local ver="${VERSION_ID%%.*}"  # major version only
  local kernel
  kernel="$(uname -r)"

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
    rhel:8)    echo "Detected: Red Hat Enterprise Linux 8" ;;
    rhel:9)    echo "Detected: Red Hat Enterprise Linux 9" ;;
    centos:8|centos_stream:8|centos-stream:8)
              echo "Detected: CentOS Stream 8" ;;
    centos:9|centos_stream:9|centos-stream:9)
              echo "Detected: CentOS Stream 9" ;;
    *)
      echo "ERROR: Unsupported OS detected."
      echo
      echo "This script supports only:"
      echo "  - RHEL 8/9"
      echo "  - CentOS Stream 8/9"
      echo "  - Oracle Linux 8/9 (RHCK only)"
      echo
      echo "Detected OS details:"
      echo "  ID=$os_id"
      echo "  VERSION_ID=$VERSION_ID"
      echo "  Kernel=$kernel"
      exit 1
      ;;
  esac
}

# --- Configuration ---
NEXUS_HOST="nexus.de.mo"
REPO_NAME="illumio"

# Schemes: HTTPS for browsing, HTTP for downloads
BROWSE_SCHEME="${BROWSE_SCHEME:-https}"
DOWNLOAD_SCHEME="${DOWNLOAD_SCHEME:-https}"

BROWSE_URL="${BROWSE_SCHEME}://${NEXUS_HOST}/service/rest/repository/browse/${REPO_NAME}/"
REPO_BASE="${DOWNLOAD_SCHEME}://${NEXUS_HOST}/repository/${REPO_NAME}"

DOWNLOAD_DIR="/tmp"
CURL_OPTS="${CURL_OPTS:-}"

# --- Helper Functions ---
die() {
  echo "ERROR: $*" >&2
  exit 1
}

fetch_index() {
  echo "Fetching repository index from:"
  echo "  ${BROWSE_URL}"
  curl -fsSL ${CURL_OPTS} "${BROWSE_URL}" ||
    die "Failed to fetch repository index."
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
  [[ -n "${filename}" ]] || die "download_file(): no filename provided"

  local url="${REPO_BASE}/${filename}"
  local dest="${DOWNLOAD_DIR}/${filename}"

  echo "Downloading:"
  echo "  ${url}"
  echo "  -> ${dest}"

  curl -fSL ${CURL_OPTS} "${url}" -o "${dest}" \
    || die "Failed to download ${filename}"
}

# --- Main ---
main() {
  check_supported_os

  . /etc/os-release
  local os_id="${ID,,}"
  local ver="${VERSION_ID%%.*}"
  local pce_major=""

  case "${os_id}:${ver}" in
    rhel:8|centos:8|centos_stream:8|centos-stream:8|ol:8|oraclelinux:8)
      pce_major="el8" ;;
    rhel:9|centos:9|centos_stream:9|centos-stream:9|ol:9|oraclelinux:9)
      pce_major="el9" ;;
    *)
      die "Unexpected OS combination (${os_id}:${ver})"
      ;;
  esac

  echo "Will select illumio-pce package for ${pce_major}"

  local index_html
  index_html="$(fetch_index)"

  mapfile -t FILENAMES < <(echo "${index_html}" | extract_filenames)

  [[ "${#FILENAMES[@]}" -gt 0 ]] ||
    die "No illumio* files found in repo."

  echo "Found files:"
  printf '  %s\n' "${FILENAMES[@]}"
  echo

  # Version-agnostic regex patterns
  local PCE_PATTERN="^illumio-pce-.*\.${pce_major}\.x86_64\.rpm$"
  local PCE_UI_PATTERN="^illumio-pce-ui-.*\.x86_64\.rpm$"
  local REL_COMP_PATTERN="^illumio-release-compatibility-.*\.tar\.bz2$"
  local VEN_BUNDLE_PATTERN="^illumio-ven-bundle-.*\.tar\.bz2$"
  local VEN_PKGS_PATTERN="^illumio-ven-pkgs-.*\.tgz$"

  # Pick latest version of each
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
  ls -lh "${DOWNLOAD_DIR}"/illumio-* 2>/dev/null || true
}

main "$@"
