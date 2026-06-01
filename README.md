

# Universal NetBird Installer Script

An improved, context-aware standalone installation engine for provisioning the NetBird mesh VPN client across Linux distributions, macOS machines, and Windows.

The scripts automatically determine the context of the host machine at runtime. They distinguish between **server/headless environments** and **graphical desktop environments**, ensuring that servers are provisioned with CLI-only tools and avoiding unnecessary GUI packages (`netbird-ui`).

---

##  Features

* **Auto-Environment Detection:** Dynamically detects whether a machine is a headless server or a GUI-based desktop.
* **Mac Server / Headless Support:** On headless macOS machines (such as remote CI/CD runners), it automatically bypasses the official desktop `.pkg` installer and installs *only* the core `netbird` CLI binary.
* **Linux Package Optimization:** On headless Linux servers, it registers native repositories but skips installation of the `netbird-ui` package, keeping server dependencies clean.
* **Windows Server / Desktop Support:** On Windows Server, it installs the CLI binary and Windows service only. On Windows Desktop, it installs the MSI with UI support.
* **Environment Overrides:** Provides manual control to force GUI installation or omission regardless of the auto-detection.

---

##  Usage

### Linux and macOS: running locally
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

### Linux and macOS: running via `curl` directly from GitHub
Because this repository is public, the raw scripts can be fetched without GitHub authentication:

* **Standard Installation (Recommended):**
  ```bash
  curl -fsSL https://raw.githubusercontent.com/skyengpro/global-gateway-agent/main/install.sh | sudo sh
  ```

* **Force CLI-only installation (Skip GUI):**
  ```bash
  curl -fsSL https://raw.githubusercontent.com/skyengpro/global-gateway-agent/main/install.sh | sudo SKIP_UI_APP=true sh
  ```

* **Force GUI installation:**
  ```bash
  curl -fsSL https://raw.githubusercontent.com/skyengpro/global-gateway-agent/main/install.sh | sudo SKIP_UI_APP=false sh
  ```

---

### Windows: running locally
Run from an elevated PowerShell session:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
.\install.ps1
```

Force CLI-only installation:

```powershell
$env:SKIP_UI_APP = "true"
.\install.ps1
```

Force UI installation:

```powershell
$env:SKIP_UI_APP = "false"
.\install.ps1
```

### Windows: running via `irm` directly from GitHub
Run from an elevated PowerShell session:

```powershell
irm https://raw.githubusercontent.com/skyengpro/global-gateway-agent/main/install.ps1 | iex
```

Force CLI-only installation:

```powershell
$env:SKIP_UI_APP = "true"; irm https://raw.githubusercontent.com/skyengpro/global-gateway-agent/main/install.ps1 | iex
```

Force UI installation:

```powershell
$env:SKIP_UI_APP = "false"; irm https://raw.githubusercontent.com/skyengpro/global-gateway-agent/main/install.ps1 | iex
```

By default, Windows Server skips the UI and Windows Desktop installs it.

---

##  Verification

Once the script completes, you can verify if the GUI agent was skipped.

Linux and macOS:

```bash
# 1. Verify the NetBird service daemon is active
sudo systemctl status netbird

# 2. Check if the GUI helper exists (should return nothing on server installations)
which netbird-ui
```

Windows:

```powershell
Get-Service netbird
Get-Command netbird-ui.exe -ErrorAction SilentlyContinue
```

---

##  Cleanup / Uninstall

Companion cleanup scripts are provided to completely remove NetBird (daemon, UI, config, and repository sources), leaving the machine in a clean state ready for a fresh installation.

On Linux and macOS, `cleanup.sh` auto-detects the OS and the original package manager used (`apt`, `dnf`, `yum`, `rpm-ostree`, `brew`, or direct binary), then removes everything cleanly.

On Windows, `uninstall.ps1` removes the NetBird service, MSI installation, CLI binary, UI processes, scheduled tasks, machine PATH entry, and local NetBird data directories.

### Linux and macOS: running cleanup locally
```bash
chmod +x cleanup.sh
sudo ./cleanup.sh
```

### Linux and macOS: running cleanup via `curl` from GitHub

* **Linux or macOS:**
  ```bash
  curl -fsSL https://raw.githubusercontent.com/skyengpro/global-gateway-agent/main/cleanup.sh | sudo sh
  ```

### Windows: running uninstall locally
Run from an elevated PowerShell session:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
.\uninstall.ps1
```

### Windows: running uninstall via `irm` from GitHub
Run from an elevated PowerShell session:

```powershell
irm https://raw.githubusercontent.com/skyengpro/global-gateway-agent/main/uninstall.ps1 | iex
```

> [!CAUTION]
> This is a **destructive operation**. It will completely remove NetBird, all its configuration files, and registered peer data. After running this, you will need to re-run the installer and re-register the peer with `netbird up`.
