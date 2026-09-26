#!/bin/bash

# ==============================================================================
# filmai_login.sh - Automated Login & Daily Bonus Script for filmai.in
# (Cloudflare WARP isolated proxy via Gluetun Docker container)
#
# Compatible with Raspberry Pi (ARMv7 32-bit / AArch64 64-bit), Ubuntu, Debian.
#
# USAGE:
#   ./filmai_login.sh           # Normal run (with randomized anti-bot delay)
#   ./filmai_login.sh debug     # Immediate execution with verbose output
#   ./filmai_login.sh update    # Check GitHub and self-update to latest release
#   ./filmai_login.sh version   # Display current script version
#   ./filmai_login.sh help      # Display help text
# ==============================================================================

CURRENT_VERSION="1.0.0"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "$0")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

GITHUB_REPO="${GITHUB_REPO:-"syncck/filmai-login"}"
GITHUB_RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main"

# ==============================================================================
# Helper & Diagnostic Functions
# ==============================================================================

show_help() {
    echo "filmai_login v${CURRENT_VERSION}"
    echo "Usage: $(basename "$0") [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  (no args)    Run login with randomized anti-bot delay (suitable for cron)"
    echo "  debug        Run immediately without delay, single attempt, verbose logging"
    echo "  update       Check for updates on GitHub and self-update"
    echo "  version      Print version information"
    echo "  help         Show this help message"
    echo ""
    echo "Config file location: ~/.config/filmai-login/.filmai_credentials"
    exit 0
}

show_version() {
    echo "filmai_login version ${CURRENT_VERSION}"
    exit 0
}

# ==============================================================================
# Self-Update Mechanism
# ==============================================================================

perform_update() {
    local silent_mode=${1:-0}

    [ "$silent_mode" -eq 0 ] && echo "Checking for updates from ${GITHUB_REPO}..."

    # Read remote VERSION
    local remote_version
    remote_version=$(curl -fsSL --connect-timeout 8 "${GITHUB_RAW_URL}/VERSION" 2>/dev/null | tr -d '[:space:]')

    if [ -z "$remote_version" ]; then
        if [ "$silent_mode" -eq 0 ]; then
            echo "ERROR: Could not retrieve version info from GitHub."
            echo "URL checked: ${GITHUB_RAW_URL}/VERSION"
            echo "If your repository is private or renamed, configure GITHUB_REPO in ~/.config/filmai-login/.filmai_credentials"
        fi
        return 1
    fi

    if [ "$remote_version" = "$CURRENT_VERSION" ]; then
        [ "$silent_mode" -eq 0 ] && echo "filmai_login is already up to date (v${CURRENT_VERSION})."
        return 0
    fi

    echo "New version available: v${remote_version} (current: v${CURRENT_VERSION})"
    echo "Downloading update..."

    local temp_script
    temp_script=$(mktemp "${SCRIPT_DIR}/filmai_login_tmp.XXXXXX")
    local temp_compose
    temp_compose=$(mktemp "${SCRIPT_DIR}/docker_compose_tmp.XXXXXX")

    if ! curl -fsSL --connect-timeout 15 "${GITHUB_RAW_URL}/filmai_login.sh" -o "$temp_script"; then
        echo "ERROR: Failed to download updated script."
        rm -f "$temp_script" "$temp_compose"
        return 1
    fi

    if ! curl -fsSL --connect-timeout 15 "${GITHUB_RAW_URL}/docker-compose.yml" -o "$temp_compose"; then
        echo "ERROR: Failed to download updated docker-compose.yml."
        rm -f "$temp_script" "$temp_compose"
        return 1
    fi

    # Verify script content is valid
    if ! head -1 "$temp_script" | grep -q "bash" || ! grep -q "filmai_login" "$temp_script"; then
        echo "ERROR: Downloaded script appears invalid or corrupted. Aborting update."
        rm -f "$temp_script" "$temp_compose"
        return 1
    fi

    # Apply updates
    chmod +x "$temp_script"
    mv -f "$temp_script" "$SCRIPT_PATH"
    mv -f "$temp_compose" "${SCRIPT_DIR}/docker-compose.yml"
    echo "$remote_version" > "${SCRIPT_DIR}/VERSION"

    echo "Update successful! Now running version v${remote_version}."
    return 0
}

# Process standalone CLI options
case "${1:-}" in
    -h|--help|help)
        show_help
        ;;
    -v|--version|version)
        show_version
        ;;
    -u|--update|update)
        perform_update 0
        exit $?
        ;;
esac

# ==============================================================================
# Credentials & Configuration Loading
# ==============================================================================

# Search paths for credentials file
CREDENTIALS_FILE=""
if [ -f "$HOME/.config/filmai-login/.filmai_credentials" ]; then
    CREDENTIALS_FILE="$HOME/.config/filmai-login/.filmai_credentials"
elif [ -f "$HOME/.filmai_credentials" ]; then
    CREDENTIALS_FILE="$HOME/.filmai_credentials"
elif [ -f "${SCRIPT_DIR}/.filmai_credentials" ]; then
    CREDENTIALS_FILE="${SCRIPT_DIR}/.filmai_credentials"
fi

if [ -z "$CREDENTIALS_FILE" ] || [ ! -f "$CREDENTIALS_FILE" ]; then
    echo "ERROR: Credentials file not found."
    echo "Please create ~/.config/filmai-login/.filmai_credentials with:"
    echo "  USERNAME=\"your_username\""
    echo "  PASSWORD=\"your_password\""
    echo "  WIREGUARD_PRIVATE_KEY=\"your_private_key\""
    echo "  WIREGUARD_ADDRESSES=\"172.16.0.2/32\""
    echo "  AUTO_UPDATE=true"
    echo ""
    echo "Then set permissions: chmod 600 ~/.config/filmai-login/.filmai_credentials"
    exit 1
fi

# Source credentials file
source "$CREDENTIALS_FILE"

# Validate required variables
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "ERROR: USERNAME or PASSWORD missing in $CREDENTIALS_FILE"
    exit 1
fi

if [ -z "$WIREGUARD_PRIVATE_KEY" ] || [ -z "$WIREGUARD_ADDRESSES" ]; then
    echo "ERROR: WIREGUARD_PRIVATE_KEY or WIREGUARD_ADDRESSES missing in $CREDENTIALS_FILE"
    exit 1
fi

# Application and runtime paths (defaults to script directory)
APP_DIR="${APP_DIR:-$SCRIPT_DIR}"
DOCKER_COMPOSE_FILE="${APP_DIR}/docker-compose.yml"
COOKIE_FILE="${APP_DIR}/filmai_cookies.txt"
LOG_FILE="${APP_DIR}/filmai_login.log"

# Export variables for Docker Compose substitution
export WIREGUARD_PRIVATE_KEY="${WIREGUARD_PRIVATE_KEY}"
export WIREGUARD_ADDRESSES="${WIREGUARD_ADDRESSES}"

# Target URLs and Proxy endpoint
BASE_URL="https://filmai.in"
LOGIN_URL="${BASE_URL}/login"
CF_TRACE_URL="https://www.cloudflare.com/cdn-cgi/trace"
IP_CHECK_URL="http://ip-api.com/json"
PROXY_PORT="${PROXY_PORT:-8888}"
export PROXY_PORT="${PROXY_PORT}"
PROXY_SERVER="http://127.0.0.1:${PROXY_PORT}"

# ==============================================================================
# Logging & Cleanup
# ==============================================================================

log_message() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOG_FILE"
    if [ "${DEBUG_MODE:-0}" -eq 1 ]; then
        echo "$msg"
    fi
}

log_separator() {
    echo "--------------------------------------------------------------------------------" >> "$LOG_FILE"
}

cleanup() {
    log_message "Script interrupted. Cleaning up..."
    manage_proxy stop
    exit 1
}
trap cleanup INT TERM

# Random Anti-Bot Delay
perform_random_delay() {
    local min_delay=${1:-60}
    local max_delay=${2:-600}
    local delay=0

    if command -v shuf &> /dev/null; then
        delay=$(shuf -i "$min_delay-$max_delay" -n 1)
    else
        delay=$(awk -v min="$min_delay" -v max="$max_delay" \
                'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
    fi

    log_message "Anti-Bot: Sleeping until $(date -d "+$delay seconds" +"%H:%M:%S" 2>/dev/null || date -v +${delay}S +"%H:%M:%S" 2>/dev/null || echo "later")..."
    sleep "$delay"
}

# ==============================================================================
# Docker & Proxy Management
# ==============================================================================

manage_proxy() {
    local action="$1"

    case "$action" in
        start)
            log_message "Starting WARP proxy"
            docker compose -f "$DOCKER_COMPOSE_FILE" up -d >/dev/null 2>&1
            if [ $? -ne 0 ]; then
                log_message "ERROR: Failed to start Docker container. Check docker compose configuration."
                return 1
            fi

            # Wait for WARP connection to establish
            local WARP_READY=0
            local TRACE_OUTPUT=""

            for i in {1..25}; do
                TRACE_OUTPUT=$(curl -s --connect-timeout 4 -x "$PROXY_SERVER" "$CF_TRACE_URL" 2>/dev/null)
                if echo "$TRACE_OUTPUT" | grep -q "warp=on"; then
                    WARP_READY=1
                    break
                fi
                sleep 2
            done

            if [ $WARP_READY -eq 0 ]; then
                log_message "ERROR: WARP proxy not ready or 'warp=on' missing."
                log_message "  Trace Output: ${TRACE_OUTPUT:-NONE}"
                return 1
            fi

            log_message "OK: \"warp=on\"."

            # Check IP details from ip-api (diagnostic)
            PROXY_INFO=$(curl -s --connect-timeout 10 -x "$PROXY_SERVER" "$IP_CHECK_URL" 2>/dev/null)
            if [ -n "$PROXY_INFO" ]; then
                IP_ADDR=$(echo "$PROXY_INFO" | grep -oP '"query":"\K[^"]+')
                COUNTRY=$(echo "$PROXY_INFO" | grep -oP '"country":"\K[^"]+')
                ISP=$(echo "$PROXY_INFO" | grep -oP '"isp":"\K[^"]+')
                log_message "IP = ${IP_ADDR:-unknown}, Country = ${COUNTRY:-unknown}, ISP = ${ISP:-unknown}."
            fi

            # GET the login page to extract CSRF token and set session cookies
            log_message "Login attempt"
            PAGE_CONTENT=$(curl -s -L \
                --cookie-jar "$COOKIE_FILE" \
                --write-out "HTTP_CODE:%{http_code}" \
                --output - \
                -x "$PROXY_SERVER" \
                --connect-timeout 60 \
                --max-time 180 \
                --retry 3 \
                --retry-delay 5 \
                "${BASE_URL}/prisijungti")

            RESPONSE_CODE=$(echo "$PAGE_CONTENT" | grep -oP 'HTTP_CODE:\K\d+')
            PAGE_CONTENT=$(echo "$PAGE_CONTENT" | sed 's/HTTP_CODE:[0-9]*//')

            if [ "$RESPONSE_CODE" = "000" ] || [ -z "$RESPONSE_CODE" ]; then
                log_message "ERROR: Connection failed (no HTTP response received). Proxy might be unstable."
                return 1
            elif [ "$RESPONSE_CODE" -ne 200 ]; then
                log_message "ERROR: Failed to load login page. HTTP status code: $RESPONSE_CODE"
                return 1
            fi

            # Save login page HTML for debugging
            echo "$PAGE_CONTENT" > "${APP_DIR}/login_page.html"

            # Extract CSRF token
            CSRF_TOKEN=$(echo "$PAGE_CONTENT" | grep -oP "var csrf_token = '\K[^']+")

            if [ -z "$CSRF_TOKEN" ]; then
                log_message "ERROR: Failed to extract CSRF token. Check login_page.html structure."
                return 1
            fi

            POST_DATA="login=${USERNAME}&password=${PASSWORD}&csrf_token=${CSRF_TOKEN}&recaptcha=&honeypot=&remember_this=1"

            sleep 3
            LOGIN_RESPONSE=$(curl -s -L \
                --cookie "$COOKIE_FILE" \
                --cookie-jar "$COOKIE_FILE" \
                --data "$POST_DATA" \
                --output "${APP_DIR}/login_response.html" \
                --write-out "%{http_code}" \
                -x "$PROXY_SERVER" \
                --connect-timeout 60 \
                --max-time 180 \
                --retry 3 \
                --retry-delay 5 \
                "${LOGIN_URL}")

            if [ "$LOGIN_RESPONSE" -ne 302 ] && [ "$LOGIN_RESPONSE" -ne 200 ]; then
                log_message "ERROR: Login POST failed. HTTP status code: $LOGIN_RESPONSE"
                return 1
            fi

            # Check if login succeeded by requesting main page
            sleep 3
            FINAL_PAGE=$(curl -s -L \
                --cookie "$COOKIE_FILE" \
                -x "$PROXY_SERVER" \
                --connect-timeout 60 \
                --max-time 180 \
                --retry 3 \
                --retry-delay 5 \
                "${BASE_URL}")

            echo "$FINAL_PAGE" > "${APP_DIR}/final_page.html"

            if ! echo "$FINAL_PAGE" | grep -q "Atsijungti"; then
                log_message "ERROR: 'Atsijungti' not found on home page. Login may have failed."
                return 1
            fi

            CURRENT_POINTS=$(echo "$FINAL_PAGE" | grep -oP "<span class='user_movie_points_span'>\K[^<]+" | head -n 1)
            log_message "OK:  Current points: ${CURRENT_POINTS:-unknown}."

            # Check if Bonus Button exists (accPointsTransBtn)
            if ! echo "$FINAL_PAGE" | grep -q ".*<button.*accPointsTransBtn.*data-ob=\"free\""; then
                log_message "ERROR: Bonus button not found. Claimed today or resistivity to script."
                log_message " > Check 'final_page.html' for details. Wont retry anymore."
                return 0
            fi

            # Bonus button found. Submitting claim request
            sleep 4
            RESPONSE=$(curl -s -L \
                --cookie "$COOKIE_FILE" \
                --cookie-jar "$COOKIE_FILE" \
                --data "do=pointstr&ob=free" \
                --write-out "HTTP_CODE:%{http_code}" \
                -x "$PROXY_SERVER" \
                --connect-timeout 60 \
                --max-time 180 \
                --retry 3 \
                --retry-delay 5 \
                "${BASE_URL}/index.php")

            HTTP_CODE=$(echo "$RESPONSE" | grep -oP 'HTTP_CODE:\K\d+')
            RESPONSE_BODY=$(echo "$RESPONSE" | sed 's/HTTP_CODE:[0-9]*//')

            if [ "$HTTP_CODE" -ne 200 ]; then
                log_message "ERROR: Bonus claim failed. HTTP Status: $HTTP_CODE"
                log_message " > Response Json: $RESPONSE_BODY"
                return 1
            fi

            if echo "$RESPONSE_BODY" | grep -q '"status":"OK"'; then
                NEW_POINTS=$(echo "$RESPONSE_BODY" | grep -oP '"points_tot":"?\K[^",}]+')
                log_message "SUCCESS: New points: $NEW_POINTS."
            else
                log_message "ERROR: Bonus claim failed."
                log_message " > Response Json: $RESPONSE_BODY"
            fi
            return 0
            ;;

        stop)
            docker compose -f "$DOCKER_COMPOSE_FILE" down >/dev/null 2>&1
            if [ $? -ne 0 ]; then
                log_message "WARNING: Failed to cleanly stop Docker container."
                return 1
            fi
            log_message "WARP proxy stopped."
            return 0
            ;;

        *)
            log_message "ERROR: Invalid action '$action'. Use 'start' or 'stop'."
            return 1
            ;;
    esac
}

# ==============================================================================
# Main Execution Loop
# ==============================================================================

mkdir -p "$APP_DIR"
log_separator

# Check auto-update if enabled in credentials
if [ "${AUTO_UPDATE:-false}" = "true" ]; then
    perform_update 1
fi

MAX_PROXY_RETRIES=3
PROXY_RETRY_COUNT=0
PROXY_ESTABLISHED=0

DEBUG_MODE=0
if [ "${1:-}" = "debug" ]; then
    log_message "INFO: Debug mode enabled (single run, immediate execution)."
    DEBUG_MODE=1
    MAX_PROXY_RETRIES=1
fi

while [ $PROXY_RETRY_COUNT -lt $MAX_PROXY_RETRIES ] && [ $PROXY_ESTABLISHED -eq 0 ]; do
    if [ $PROXY_RETRY_COUNT -gt 0 ]; then
        log_message "Retry attempt $((PROXY_RETRY_COUNT + 1))/$MAX_PROXY_RETRIES"
    fi

    if [ $DEBUG_MODE -eq 0 ]; then
        perform_random_delay 30 7500
    fi

    manage_proxy start
    if [ $? -eq 0 ]; then
        PROXY_ESTABLISHED=1
        manage_proxy stop
    else
        manage_proxy stop
        PROXY_RETRY_COUNT=$((PROXY_RETRY_COUNT + 1))
        sleep 10
    fi
done

if [ $PROXY_ESTABLISHED -eq 0 ]; then
    log_message "CRITICAL ERROR: Max retries reached ($MAX_PROXY_RETRIES). Could not complete login."
    exit 1
fi

exit 0
