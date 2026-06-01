

# Universal NetBird Installer Script

An improved, context-aware standalone installation engine for provisioning the NetBird mesh VPN client across Linux distributions and macOS machines.

This script automatically determines the context of the host machine at runtime. It distinguishes between **headless server environments** and **graphical desktop environments**, ensuring that servers are provisioned with CLI-only tools and avoiding unnecessary GUI packages (`netbird-ui`).

---

## ✨ Features

* **Auto-Environment Detection:** Dynamically detects whether a machine is a headless server or a GUI-based desktop.
* **Mac Server / Headless Support:** On headless macOS machines (such as remote CI/CD runners), it automatically bypasses the official desktop `.pkg` installer and installs *only* the core `netbird` CLI binary.
* **Linux Package Optimization:** On headless Linux servers, it registers native repositories but skips installation of the `netbird-ui` package, keeping server dependencies clean.
* **Environment Overrides:** Provides manual control to force GUI installation or omission regardless of the auto-detection.

---

## 🚀 Usage

### Option 1: Running the Script Locally
If you have cloned the repository locally:

1. **Make the script executable:**
   ```bash
   chmod +x install.sh
   ```

2. **Standard Installation (Recommended):**
   ```bash
   sudo ./install.sh
   ```

3. **Override Settings (Optional):**
   * **Force CLI-only installation (Skip GUI):**
     ```bash
     sudo SKIP_UI_APP=true ./install.sh
     ```
   * **Force GUI installation:**
     ```bash
     sudo SKIP_UI_APP=false ./install.sh
     ```

---

### Option 2: Running via `curl` directly from GitHub (Private Repository)
Because this repository is private, GitHub returns a `404 Not Found` for unauthenticated requests. To run the script remotely, you must authenticate the `curl` request using a GitHub Personal Access Token (PAT) with `read` permissions for the repository:

* **Standard Installation (Recommended):**
  ```bash
  curl -fsSL -H "Authorization: token YOUR_GITHUB_PAT" \
    https://raw.githubusercontent.com/skyengpro/global-gateway-agent/main/install.sh | sudo sh
  ```

* **Force CLI-only installation (Skip GUI):**
  ```bash
  curl -fsSL -H "Authorization: token YOUR_GITHUB_PAT" \
    https://raw.githubusercontent.com/skyengpro/global-gateway-agent/main/install.sh | sudo SKIP_UI_APP=true sh
  ```

* **Force GUI installation:**
  ```bash
  curl -fsSL -H "Authorization: token YOUR_GITHUB_PAT" \
    https://raw.githubusercontent.com/skyengpro/global-gateway-agent/main/install.sh | sudo SKIP_UI_APP=false sh
  ```

#### **Alternative: Using Basic Authentication**
You can also pass your GitHub username and token using basic auth:
```bash
curl -fsSL -u "USERNAME:YOUR_GITHUB_PAT" \
  https://raw.githubusercontent.com/skyengpro/global-gateway-agent/main/install.sh | sudo sh
```

---

## 🔍 Verification

Once the script completes, you can verify if the GUI agent was skipped:

```bash
# 1. Verify the NetBird service daemon is active
sudo systemctl status netbird

# 2. Check if the GUI helper exists (should return nothing on server installations)
which netbird-ui
```

---

## 🧹 Cleanup / Uninstall

A companion `cleanup.sh` script is provided to completely remove NetBird (daemon, UI, config, and repository sources) from any Linux or macOS machine, leaving it in a clean state ready for a fresh installation.

It auto-detects the OS and the original package manager used (`apt`, `dnf`, `yum`, `rpm-ostree`, `brew`, or direct binary), then removes everything cleanly.

### Option 1: Running cleanup locally
```bash
chmod +x cleanup.sh
sudo ./cleanup.sh
```

### Option 2: Running cleanup via `curl` from GitHub

* **Linux or macOS:**
  ```bash
  curl -fsSL -H "Authorization: token YOUR_GITHUB_PAT" \
    https://raw.githubusercontent.com/skyengpro/global-gateway-agent/main/cleanup.sh | sudo sh
  ```

> [!CAUTION]
> This is a **destructive operation**. It will completely remove NetBird, all its configuration files, and registered peer data. After running this, you will need to re-run `install.sh` and re-register the peer with `netbird up`.
