#!/bin/sh
# NetBird Cleanup Script
# Completely removes NetBird (daemon, UI, config, repos) from Linux and macOS machines.
# Safe to re-run — all steps handle already-missing resources gracefully.
set -e

SUDO=""
if command -v sudo >/dev/null && [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
elif command -v doas >/dev/null && [ "$(id -u)" -ne 0 ]; then
    SUDO="doas"
fi

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────
info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }
warn()    { echo "[WARN]  $*"; }

stop_service() {
    info "Stopping and uninstalling NetBird service..."
    ${SUDO} netbird service stop    >/dev/null 2>&1 || warn "Service was not running."
    ${SUDO} netbird service uninstall >/dev/null 2>&1 || warn "Service was not registered."
}

remove_config() {
    info "Removing NetBird config, logs, and runtime data..."
    # System-level dirs
    ${SUDO} rm -rf /etc/netbird /var/lib/netbird /var/log/netbird
    # Runtime socket
    ${SUDO} rm -f /var/run/netbird.sock
    # User-level config (Linux: ~/.config/netbird, macOS: ~/Library/...)
    rm -rf "${HOME}/.config/netbird"
    rm -rf "${HOME}/Library/Application Support/netbird" 2>/dev/null || true
    rm -rf "${HOME}/Library/Logs/netbird" 2>/dev/null || true
    ${SUDO} rm -f "${HOME}/Library/Preferences/io.netbird."* 2>/dev/null || true
    success "Config, logs, and runtime data removed."
}

# ─────────────────────────────────────────────
# macOS Cleanup
# ─────────────────────────────────────────────
cleanup_macos() {
    info "Detected macOS. Starting cleanup..."

    stop_service

    # Remove CLI binary
    if [ -f /usr/local/bin/netbird ]; then
        ${SUDO} rm -f /usr/local/bin/netbird
        success "Removed /usr/local/bin/netbird"
    else
        warn "/usr/local/bin/netbird not found — skipping."
    fi

    # Remove GUI app bundle
    if [ -d "/Applications/NetBird UI.app" ]; then
        ${SUDO} rm -rf "/Applications/NetBird UI.app"
        success "Removed /Applications/NetBird UI.app"
    else
        warn "NetBird UI.app not found in /Applications — skipping."
    fi

    # Remove Homebrew installations if present
    if command -v brew >/dev/null 2>&1; then
        if brew ls --versions netbird >/dev/null 2>&1; then
            info "Removing Homebrew netbird..."
            brew uninstall netbird >/dev/null 2>&1 && success "Removed brew netbird"
        fi
        if brew ls --versions netbird-ui >/dev/null 2>&1; then
            info "Removing Homebrew netbird-ui cask..."
            brew uninstall --cask netbird-ui >/dev/null 2>&1 && success "Removed brew netbird-ui"
        fi
    fi

    # Remove LaunchDaemon plist (registered by netbird service install)
    if [ -f /Library/LaunchDaemons/io.netbird.client.plist ]; then
        ${SUDO} launchctl unload /Library/LaunchDaemons/io.netbird.client.plist >/dev/null 2>&1 || true
        ${SUDO} rm -f /Library/LaunchDaemons/io.netbird.client.plist
        success "Removed LaunchDaemon plist."
    fi

    # Remove pkg installer receipts
    if [ -f /Library/Receipts/netbird.pkg ]; then
        ${SUDO} rm -f /Library/Receipts/netbird.pkg
        success "Removed pkg receipt."
    fi
    ${SUDO} pkgutil --forget io.netbird.client    >/dev/null 2>&1 || true
    ${SUDO} pkgutil --forget io.netbird.netbird-ui >/dev/null 2>&1 || true

    remove_config

    success "macOS cleanup complete. NetBird has been fully removed."
}

# ─────────────────────────────────────────────
# Linux Cleanup
# ─────────────────────────────────────────────
cleanup_linux() {
    info "Detected Linux. Starting cleanup..."

    stop_service

    # Detect package manager and uninstall
    if [ -x "$(command -v apt-get)" ]; then
        info "Removing packages via apt..."
        ${SUDO} apt-get purge -y netbird netbird-ui >/dev/null 2>&1 || warn "One or both packages were not installed."
        ${SUDO} apt-get autoremove -y >/dev/null 2>&1 || true
        # Remove repo sources and GPG keys
        ${SUDO} rm -f \
            /etc/apt/sources.list.d/netbird.list \
            /etc/apt/sources.list.d/wiretrustee.list \
            /usr/share/keyrings/netbird-archive-keyring.gpg \
            /usr/share/keyrings/wiretrustee-archive-keyring.gpg
        ${SUDO} apt-get update >/dev/null 2>&1
        success "Removed apt packages and repository sources."

    elif [ -x "$(command -v dnf)" ]; then
        info "Removing packages via dnf..."
        ${SUDO} dnf remove -y netbird netbird-ui >/dev/null 2>&1 || warn "One or both packages were not installed."
        ${SUDO} rm -f /etc/yum.repos.d/netbird.repo
        ${SUDO} dnf clean all >/dev/null 2>&1 || true
        success "Removed dnf packages and repository sources."

    elif [ -x "$(command -v yum)" ]; then
        info "Removing packages via yum..."
        ${SUDO} yum remove -y netbird netbird-ui >/dev/null 2>&1 || warn "One or both packages were not installed."
        ${SUDO} rm -f /etc/yum.repos.d/netbird.repo
        success "Removed yum packages and repository sources."

    elif [ -x "$(command -v rpm-ostree)" ]; then
        info "Removing packages via rpm-ostree..."
        ${SUDO} rpm-ostree uninstall netbird netbird-ui >/dev/null 2>&1 || warn "One or both packages were not installed."
        ${SUDO} rm -f /etc/yum.repos.d/netbird.repo
        success "Removed rpm-ostree packages and repository sources."

    else
        # Binary install — remove binaries directly
        info "No standard package manager detected. Removing binaries directly..."
        ${SUDO} rm -f /usr/bin/netbird /usr/bin/netbird-ui /usr/local/bin/netbird /usr/local/bin/netbird-ui
        success "Removed NetBird binaries."
    fi

    # Remove systemd unit file if leftover
    if [ -f /etc/systemd/system/netbird.service ]; then
        ${SUDO} rm -f /etc/systemd/system/netbird.service
        ${SUDO} systemctl daemon-reload >/dev/null 2>&1 || true
        success "Removed leftover systemd unit."
    fi

    remove_config

    success "Linux cleanup complete. NetBird has been fully removed."
}

# ─────────────────────────────────────────────
# Entry Point
# ─────────────────────────────────────────────
case "$(uname)" in
    Darwin) cleanup_macos ;;
    Linux)  cleanup_linux ;;
    *)
        echo "[ERROR] Unsupported OS: $(uname). Only Linux and macOS are supported."
        exit 1
    ;;
esac
