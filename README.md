# filmai-login automatic script

Filmai.in awards a daily +0.5 points bonus when user logs in through Cloudflare WARP. This script automates the login and bonus claim process on a scheduled basis.

To run, configure the credentials file with your filmai.in login details and Cloudflare WARP WireGuard keys.

Setup a cronjob to run the script on a schedule (e.g. when you are not going to use the website, e.g. at night). Once started, the script random delays - postpones the login. So if you start it at 9am, it may login at 9am+2hours or 9am+4hours (Random).

## How It Works

1. Starts a temporary Docker proxy container (`gluetun`) configured with Cloudflare WARP via WireGuard.
2. Verifies the tunnel connection status (`warp=on`).
3. Fetches CSRF tokens and submits login credentials.
4. Checks the user dashboard for the free bonus claim button.
5. Clicks the claim button if available.
6. Verifies point balance update and records it to log.
7. Stops and cleans up the proxy container.

## Installation & Setup

### 1. Prerequisites

Ensure Docker is installed and the Linux TUN module is available (required by WireGuard to create network tunnels):

```bash
# Install Docker (if not present)
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER && newgrp docker

# Check TUN kernel device (creates /dev/net/tun if missing)
ls -l /dev/net/tun || sudo modprobe tun
```

### 2. Generate Cloudflare WARP Keys

filmai.in requires traffic to originate from Cloudflare WARP to grant the daily bonus. Since the proxy connects to WARP via WireGuard, you need client WireGuard keys (`PrivateKey` and `Address`).

Generate free keys using the open-source `wgcf` tool:

```bash
# Download wgcf (example for aarch64 / ARM64 Raspberry Pi)
curl -fsSL https://github.com/ViRb3/wgcf/releases/latest/download/wgcf_2.2.22_linux_arm64 -o wgcf
chmod +x wgcf

# Register an anonymous Cloudflare WARP account and export profile
./wgcf register --accept-tos
./wgcf generate
```

This creates `wgcf-profile.conf`. You will need `PrivateKey` and `Address` from this file in the next step.

### 3. Install Script

Install via `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/syncck/filmai-login/main/install.sh | bash
```

Or via `curl`:

```bash
curl -fsSL https://raw.githubusercontent.com/syncck/filmai-login/main/install.sh | bash
```

This installs files to `/opt/filmai-login` and links the command to `/usr/local/bin/filmai-login`.

### 4. Configure Credentials

Edit the credentials file created during installation:

```bash
nano ~/.config/filmai-login/.filmai_credentials
```

Paste your filmai.in login details and the WARP keys obtained in Step 2:

```bash
USERNAME="your_username"
PASSWORD="your_password"
WIREGUARD_PRIVATE_KEY="your_private_key_from_wgcf"
WIREGUARD_ADDRESSES="172.16.0.2/32"
AUTO_UPDATE=true
```

Set secure file permissions:

```bash
chmod 600 ~/.config/filmai-login/.filmai_credentials
```

### Port Collision Note

The proxy binds locally to `127.0.0.1:8888`. If port 8888 is already occupied on your host (e.g., Jupyter, web services, or other proxies), override it in `~/.config/filmai-login/.filmai_credentials`:

```bash
PROXY_PORT="8899"
```

## CLI Usage

```bash
filmai-login          # Standard run (includes randomized delay before execution)
filmai-login debug    # Immediate run, single attempt, verbose terminal output
filmai-login update   # Self-update script and compose files from repository
filmai-login version  # Print current version
```

Log path: `/opt/filmai-login/filmai_login.log`

## Scheduling

Edit cron table:

```bash
crontab -e
```

**Option A: Daily at a fixed time (example: 09:30 AM)**
```cron
# Runs daily at 09:30 AM (script includes random sleep interval to avoid bot patterns)
30 9 * * * /usr/local/bin/filmai-login > /dev/null 2>&1
```

**Option B: On system startup**
```cron
# Runs automatically once after every system boot
@reboot /usr/local/bin/filmai-login > /dev/null 2>&1
```
