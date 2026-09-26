#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/filmai-login"
BIN_LINK="/usr/local/bin/filmai-login"
GITHUB_REPO="syncck/filmai-login"
GITHUB_RAW="https://raw.githubusercontent.com/${GITHUB_REPO}/main"

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
CONFIG_DIR="${TARGET_HOME}/.config/filmai-login"
CREDENTIALS_FILE="${CONFIG_DIR}/.filmai_credentials"

DOWNLOADER=""
for cmd in curl wget; do
    if command -v "$cmd" >/dev/null 2>&1; then
        DOWNLOADER="$cmd"
        break
    fi
done

if [ -z "$DOWNLOADER" ]; then
    echo "curl or wget required." >&2
    exit 1
fi

download_file() {
    local url="$1"
    local dest="$2"
    if [ "$DOWNLOADER" = "curl" ]; then
        curl -fsSL "$url" -o "$dest"
    else
        wget -qO "$dest" "$url"
    fi
}

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker not detected. Install via: curl -fsSL https://get.docker.com | sudo sh" >&2
fi

SCRIPT_SOURCE_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ "${BASH_SOURCE[0]}" != "bash" ]; then
    SCRIPT_SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
fi
if [ -z "${SCRIPT_SOURCE_DIR}" ]; then
    SCRIPT_SOURCE_DIR="$(pwd)"
fi

sudo mkdir -p "$INSTALL_DIR"

if [ -f "${SCRIPT_SOURCE_DIR}/filmai_login.sh" ] && [ -f "${SCRIPT_SOURCE_DIR}/docker-compose.yml" ]; then
    sudo cp "${SCRIPT_SOURCE_DIR}/filmai_login.sh" "${INSTALL_DIR}/filmai_login.sh"
    sudo cp "${SCRIPT_SOURCE_DIR}/docker-compose.yml" "${INSTALL_DIR}/docker-compose.yml"
    if [ -f "${SCRIPT_SOURCE_DIR}/VERSION" ]; then
        sudo cp "${SCRIPT_SOURCE_DIR}/VERSION" "${INSTALL_DIR}/VERSION"
    else
        echo "1.0.0" | sudo tee "${INSTALL_DIR}/VERSION" >/dev/null
    fi
else
    tmp_script=$(mktemp)
    tmp_compose=$(mktemp)
    tmp_version=$(mktemp)
    download_file "${GITHUB_RAW}/filmai_login.sh" "$tmp_script"
    download_file "${GITHUB_RAW}/docker-compose.yml" "$tmp_compose"
    download_file "${GITHUB_RAW}/VERSION" "$tmp_version" || echo "1.0.0" >"$tmp_version"
    sudo install -m 755 "$tmp_script" "${INSTALL_DIR}/filmai_login.sh"
    sudo install -m 644 "$tmp_compose" "${INSTALL_DIR}/docker-compose.yml"
    sudo install -m 644 "$tmp_version" "${INSTALL_DIR}/VERSION"
    rm -f "$tmp_script" "$tmp_compose" "$tmp_version"
fi

sudo chmod +x "${INSTALL_DIR}/filmai_login.sh"

sudo ln -sf "${INSTALL_DIR}/filmai_login.sh" "$BIN_LINK"

sudo -u "$TARGET_USER" mkdir -p "$CONFIG_DIR"

if [ ! -f "$CREDENTIALS_FILE" ]; then
    sudo -u "$TARGET_USER" tee "$CREDENTIALS_FILE" >/dev/null <<'EOF'
# Target service credentials
USERNAME="your_username"
PASSWORD="your_password"

# WireGuard keys (from wgcf-profile.conf)
WIREGUARD_PRIVATE_KEY="your_private_key"
WIREGUARD_ADDRESSES="172.16.0.2/32"

# Auto-update from repository before each run
AUTO_UPDATE=true
EOF
    sudo chmod 600 "$CREDENTIALS_FILE"
fi

sudo chown -R "${TARGET_USER}:${TARGET_USER}" "$INSTALL_DIR"
echo "Installed to ${INSTALL_DIR}. Binary linked to ${BIN_LINK}."
