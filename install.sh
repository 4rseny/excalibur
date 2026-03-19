#!/bin/bash
# ============================================================================
#   ███████╗██╗  ██╗ ██████╗ █████╗ ██╗     ██╗██████╗ ██╗   ██╗██████╗
#   ██╔════╝╚██╗██╔╝██╔════╝██╔══██╗██║     ██║██╔══██╗██║   ██║██╔══██╗
#   █████╗   ╚███╔╝ ██║     ███████║██║     ██║██████╔╝██║   ██║██████╔╝
#   ██╔══╝   ██╔██╗ ██║     ██╔══██║██║     ██║██╔══██╗██║   ██║██╔══██╗
#   ███████╗██╔╝ ██╗╚██████╗██║  ██║███████╗██║██████╔╝╚██████╔╝██║  ██║
#   ╚══════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝
#
#                     WMI Driver + Control Panel Installer
#                       github.com/thekayrasari/excalibur
# ============================================================================
# Usage:
#   sudo ./install.sh              — interactive wizard
#   sudo ./install.sh install      — non-interactive full install
#   sudo ./install.sh uninstall    — non-interactive full uninstall
# ============================================================================
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
R='\033[0;31m'
G='\033[0;32m'
Y='\033[0;33m'
B='\033[0;34m'
C='\033[0;36m'
M='\033[0;35m'
W='\033[1;37m'
D='\033[2m'
NC='\033[0m'

# ── Constants ─────────────────────────────────────────────────────────────────
MODULE_NAME="excalibur"
KO_FILE="${MODULE_NAME}.ko"
LIB_MODULES="/lib/modules/$(uname -r)"
INSTALL_DIR="${LIB_MODULES}/extra"
MODULES_LOAD_DIR="/etc/modules-load.d"
CONTROL_PANEL_SRC="control-panel.py"
CONTROL_PANEL_DEST="/usr/local/lib/excalibur-control-panel.py"
CONTROL_PANEL_BIN="/usr/local/bin/excalibur-panel"
UDEV_RULES_FILE="/etc/udev/rules.d/99-excalibur.rules"
DESKTOP_FILE="/usr/share/applications/excalibur-panel.desktop"
INITRAMFS_CMD=""
PYTHON_BIN="python3"
CC_COMPILER="gcc"
PKG_INSTALL=""
HEADERS_PKG=""

# ── Helpers ───────────────────────────────────────────────────────────────────
print_banner() {
    echo -e "${C}"
    echo '  ███████╗██╗  ██╗ ██████╗ █████╗ ██╗     ██╗██████╗ ██╗   ██╗██████╗ '
    echo '  ██╔════╝╚██╗██╔╝██╔════╝██╔══██╗██║     ██║██╔══██╗██║   ██║██╔══██╗'
    echo '  █████╗   ╚███╔╝ ██║     ███████║██║     ██║██████╔╝██║   ██║██████╔╝ '
    echo '  ██╔══╝   ██╔██╗ ██║     ██╔══██║██║     ██║██╔══██╗██║   ██║██╔══██╗ '
    echo '  ███████╗██╔╝ ██╗╚██████╗██║  ██║███████╗██║██████╔╝╚██████╔╝██║  ██║ '
    echo '  ╚══════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝'
    echo -e "${NC}"
    echo -e "  ${W}WMI Driver + Control Panel Installer${NC}   ${D}github.com/thekayrasari/excalibur${NC}"
    echo -e "  ${D}────────────────────────────────────────────────────────────────────${NC}"
    echo ""
}

step()    { echo -e "\n${B}[${W}*${B}]${NC} ${W}${1}${NC}"; }
ok()      { echo -e "  ${G}✔${NC}  ${1}"; }
warn()    { echo -e "  ${Y}⚠${NC}  ${Y}${1}${NC}"; }
err()     { echo -e "  ${R}✘${NC}  ${R}${1}${NC}"; }
info()    { echo -e "  ${D}${1}${NC}"; }
divider() { echo -e "  ${D}────────────────────────────────────────${NC}"; }

ask() {
    local question="$1"
    local default="${2:-y}"
    local prompt
    if [[ "$default" == "y" ]]; then
        prompt="${W}[${G}Y${W}/n]${NC}"
    else
        prompt="${W}[${R}y${W}/N]${NC}"
    fi
    echo -ne "\n  ${C}?${NC}  ${question} ${prompt} "
    read -r answer
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy]$ ]]
}

require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        err "This script must be run as root."
        echo -e "  ${D}Run: ${W}sudo ./install.sh${NC}"
        exit 1
    fi
}

# ── Distro detection ──────────────────────────────────────────────────────────
detect_distro() {
    DISTRO_ID=""
    DISTRO_NAME=""
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_NAME="${PRETTY_NAME:-unknown}"
    fi
    case "$DISTRO_ID" in
        arch|manjaro|endeavouros)
            INITRAMFS_CMD="mkinitcpio -P"
            PKG_INSTALL="pacman -S --noconfirm"
            HEADERS_PKG="linux-headers"
            ;;
        ubuntu|debian|linuxmint|pop)
            INITRAMFS_CMD="update-initramfs -u"
            PKG_INSTALL="apt-get install -y"
            HEADERS_PKG="linux-headers-$(uname -r)"
            ;;
        fedora|centos|rhel|rocky|almalinux)
            INITRAMFS_CMD="dracut --force"
            PKG_INSTALL="dnf install -y"
            HEADERS_PKG="kernel-devel"
            ;;
        opensuse*|suse)
            INITRAMFS_CMD="mkinitrd"
            PKG_INSTALL="zypper install -y"
            HEADERS_PKG="kernel-devel"
            ;;
        *)
            warn "Unrecognised distro '${DISTRO_ID}'. initramfs update will be skipped."
            INITRAMFS_CMD=""
            ;;
    esac
}

# ── Compiler detection ───────────────────────────────────────────────────────
detect_compiler() {
    # The running kernel records the compiler it was built with in /proc/version.
    # If the string contains "clang", out-of-tree modules must be compiled with
    # clang (and LD=ld.lld) so that the compiler ABI matches.
    if grep -qi "clang" /proc/version 2>/dev/null; then
        CC_COMPILER="clang"
        info "Kernel was built with Clang — will use CC=clang for module build"
    else
        CC_COMPILER="gcc"
        info "Kernel was built with GCC — will use CC=gcc for module build"
    fi
}

# ── Pre-flight checks ─────────────────────────────────────────────────────────
check_build_tools() {
    local missing=()
    command -v make &>/dev/null || missing+=("make")
    if [[ "$CC_COMPILER" == "clang" ]]; then
        command -v clang &>/dev/null || missing+=("clang")
    else
        command -v gcc   &>/dev/null || missing+=("gcc")
    fi
    if [[ ${#missing[@]} -gt 0 ]]; then
        err "Missing build tools: ${missing[*]}"
        [[ -n "$PKG_INSTALL" ]] && info "Install with: ${PKG_INSTALL} ${missing[*]}"
        return 1
    fi
    ok "Build tools present (make, ${CC_COMPILER})"
}

check_kernel_headers() {
    if [[ -d "${LIB_MODULES}/build" ]]; then
        ok "Kernel headers found"
        return 0
    fi
    err "Kernel headers not found at ${LIB_MODULES}/build"
    [[ -n "$HEADERS_PKG" && -n "$PKG_INSTALL" ]] && info "Install with: ${PKG_INSTALL} ${HEADERS_PKG}"
    return 1
}

check_wmi_guid() {
    local guid="644C5791-B7B0-4123-A90B-E93876E0DAAD"
    if ls /sys/bus/wmi/devices/ 2>/dev/null | grep -qi "${guid}"; then
        ok "WMI GUID found in firmware"
    else
        warn "WMI GUID not found — driver may not bind on this machine"
    fi
}

check_python() {
    local py
    py=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)
    if [[ -z "$py" ]]; then
        err "python3 not found"
        return 1
    fi
    PYTHON_BIN="$py"
    local ver
    ver=$("$PYTHON_BIN" --version 2>&1)
    ok "Python found: ${ver}"
}

check_textual() {
    if "$PYTHON_BIN" -c "import textual" 2>/dev/null; then
        local ver
        ver=$("$PYTHON_BIN" -c "import textual; print(textual.__version__)" 2>/dev/null)
        ok "Textual ${ver} already installed"
        return 0
    fi
    return 1
}

install_textual() {
    step "Installing Textual Python library"
    if "$PYTHON_BIN" -m pip install textual 2>/dev/null; then
        ok "Textual installed"
        return 0
    fi
    if "$PYTHON_BIN" -m pip install textual --break-system-packages 2>/dev/null; then
        ok "Textual installed (--break-system-packages)"
        return 0
    fi
    err "Could not install Textual automatically."
    info "Try: sudo pip install textual --break-system-packages"
    return 1
}

# ── Driver ────────────────────────────────────────────────────────────────────
build_driver() {
    step "Building kernel module"
    if [[ ! -f "excalibur.c" || ! -f "Makefile" ]]; then
        err "excalibur.c or Makefile not found in $(pwd)"
        info "Run this script from the excalibur source directory."
        exit 1
    fi
    info "Compiler: CC=${CC_COMPILER}"
    make clean 2>/dev/null || true
    if make CC="${CC_COMPILER}"; then
        ok "Module built: ${KO_FILE}"
    else
        err "Build failed"
        exit 1
    fi
}

install_driver() {
    step "Installing kernel module"
    mkdir -p "${INSTALL_DIR}"
    cp "${KO_FILE}" "${INSTALL_DIR}/"
    depmod -a
    ok "Module installed: ${INSTALL_DIR}/${KO_FILE}"

    step "Configuring auto-load at boot"
    mkdir -p "${MODULES_LOAD_DIR}"
    echo "${MODULE_NAME}" > "${MODULES_LOAD_DIR}/${MODULE_NAME}.conf"
    ok "Auto-load config: ${MODULES_LOAD_DIR}/${MODULE_NAME}.conf"

    if [[ -n "${INITRAMFS_CMD}" ]]; then
        step "Updating initramfs"
        ${INITRAMFS_CMD} && ok "initramfs updated" || warn "initramfs update failed (non-fatal)"
    fi

    step "Loading module"
    if modprobe "${MODULE_NAME}"; then
        ok "Module loaded"
    else
        warn "modprobe failed — check: sudo dmesg | grep excalibur"
    fi
}

uninstall_driver() {
    step "Unloading kernel module"
    rmmod "${MODULE_NAME}" 2>/dev/null && ok "Module unloaded" || warn "Module was not loaded"

    step "Removing files"
    rm -f "${MODULES_LOAD_DIR}/${MODULE_NAME}.conf"
    rm -f "${INSTALL_DIR}/${KO_FILE}"
    depmod -a
    ok "Driver files removed"

    if [[ -n "${INITRAMFS_CMD}" ]]; then
        step "Updating initramfs"
        ${INITRAMFS_CMD} && ok "Done" || warn "Failed (non-fatal)"
    fi
}

# ── udev rules ────────────────────────────────────────────────────────────────
install_udev_rules() {
    step "Installing udev rules"
    cat > "${UDEV_RULES_FILE}" <<'UDEV'
# excalibur-wmi udev rules
# Grants write access to LED zones and power plan for wheel/sudo group members,
# allowing the control panel to run without sudo.

# Keyboard LED zones
SUBSYSTEM=="leds", KERNEL=="excalibur*", \
    RUN+="/bin/sh -c 'chown root:wheel /sys%p/brightness /sys%p/color /sys%p/mode /sys%p/raw 2>/dev/null; chmod g+w /sys%p/brightness /sys%p/color /sys%p/mode /sys%p/raw 2>/dev/null'", \
    RUN+="/bin/sh -c 'chown root:sudo  /sys%p/brightness /sys%p/color /sys%p/mode /sys%p/raw 2>/dev/null; chmod g+w /sys%p/brightness /sys%p/color /sys%p/mode /sys%p/raw 2>/dev/null'"

# hwmon (fan speeds + power plan)
SUBSYSTEM=="hwmon", ATTR{name}=="excalibur_wmi", \
    RUN+="/bin/sh -c 'chown root:wheel /sys%p/pwm1 /sys%p/fan1_input /sys%p/fan2_input 2>/dev/null; chmod g+rw /sys%p/pwm1 2>/dev/null'", \
    RUN+="/bin/sh -c 'chown root:sudo  /sys%p/pwm1 /sys%p/fan1_input /sys%p/fan2_input 2>/dev/null; chmod g+rw /sys%p/pwm1 2>/dev/null'"
UDEV
    udevadm control --reload-rules
    udevadm trigger
    ok "udev rules installed: ${UDEV_RULES_FILE}"
    info "Re-login (or reboot) for group permissions to take effect."
    info "Ensure your user is in the 'wheel' group (Fedora/Arch) or 'sudo' group (Debian/Ubuntu):"
    info "  sudo usermod -aG wheel \$SUDO_USER   (Fedora/Arch)"
    info "  sudo usermod -aG sudo  \$SUDO_USER   (Debian/Ubuntu)"
}

uninstall_udev_rules() {
    step "Removing udev rules"
    rm -f "${UDEV_RULES_FILE}"
    udevadm control --reload-rules
    ok "Removed ${UDEV_RULES_FILE}"
}

# ── Control panel ─────────────────────────────────────────────────────────────
install_control_panel() {
    step "Installing control panel"
    if [[ ! -f "${CONTROL_PANEL_SRC}" ]]; then
        err "${CONTROL_PANEL_SRC} not found in $(pwd)"
        exit 1
    fi

    mkdir -p "$(dirname "${CONTROL_PANEL_DEST}")"
    cp "${CONTROL_PANEL_SRC}" "${CONTROL_PANEL_DEST}"
    chmod 644 "${CONTROL_PANEL_DEST}"
    ok "Control panel source: ${CONTROL_PANEL_DEST}"

    # Write the launcher script with the correct python path baked in
    cat > "${CONTROL_PANEL_BIN}" <<LAUNCHER
#!/bin/bash
# Excalibur Control Panel launcher — auto-generated by installer
exec "${PYTHON_BIN}" "${CONTROL_PANEL_DEST}" "\$@"
LAUNCHER
    chmod 755 "${CONTROL_PANEL_BIN}"
    ok "Launcher: ${CONTROL_PANEL_BIN}"
}

install_desktop_entry() {
    step "Installing desktop entry"
    mkdir -p "$(dirname "${DESKTOP_FILE}")"
    cat > "${DESKTOP_FILE}" <<DESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=Excalibur Control Panel
GenericName=Laptop Control Panel
Comment=RGB lighting, fan monitoring and power plan control for Excalibur laptops
Exec=bash -c 'exec ${PYTHON_BIN} ${CONTROL_PANEL_DEST}'
Icon=input-keyboard
Terminal=true
Categories=System;HardwareSettings;
Keywords=excalibur;rgb;keyboard;fan;laptop;
StartupNotify=false
DESKTOP
    ok "Desktop entry: ${DESKTOP_FILE}"
}

uninstall_control_panel() {
    step "Removing control panel"
    rm -f "${CONTROL_PANEL_DEST}" "${CONTROL_PANEL_BIN}" "${DESKTOP_FILE}"
    ok "Control panel removed"
}

# ── Verify ────────────────────────────────────────────────────────────────────
verify_install() {
    step "Verifying installation"
    divider

    lsmod | grep -q "^${MODULE_NAME}" \
        && ok "Kernel module loaded" \
        || warn "Module NOT loaded — try: sudo modprobe excalibur"

    local led_count
    led_count=$(ls /sys/class/leds/ 2>/dev/null | grep -c "excalibur" || true)
    [[ "$led_count" -gt 0 ]] \
        && ok "LED sysfs nodes found (${led_count} zones)" \
        || warn "No LED sysfs nodes found yet"

    local hwmon_found=false
    for f in /sys/class/hwmon/hwmon*/name; do
        [[ "$(cat "$f" 2>/dev/null)" == "excalibur_wmi" ]] && hwmon_found=true && break
    done
    $hwmon_found && ok "hwmon device found" || warn "hwmon device not found yet"

    [[ -x "${CONTROL_PANEL_BIN}" ]] \
        && ok "Control panel launcher ready: excalibur-panel" \
        || warn "Control panel launcher not found"

    "$PYTHON_BIN" -c "import textual" 2>/dev/null \
        && ok "Textual library available" \
        || warn "Textual not importable — run: sudo pip install textual --break-system-packages"

    divider
}

# ── Interactive wizard ────────────────────────────────────────────────────────
interactive_install() {
    print_banner

    echo -e "  ${W}Welcome to the Excalibur WMI installer.${NC}"
    echo -e "  ${D}This wizard installs the kernel driver and TUI control panel.${NC}"
    echo ""
    echo -e "  ${D}System : ${W}${DISTRO_NAME:-Unknown}${NC}  |  Kernel: ${W}$(uname -r)${NC}"
    echo ""

    step "Pre-flight checks"
    divider
    check_build_tools    || { err "Cannot continue without build tools."; exit 1; }
    check_kernel_headers || { err "Cannot continue without kernel headers."; exit 1; }
    check_wmi_guid
    check_python         || { err "Cannot continue without Python 3."; exit 1; }
    divider

    # Driver
    echo ""
    echo -e "  ${M}── Kernel Driver ─────────────────────────────────────────────${NC}"
    if lsmod 2>/dev/null | grep -q "^${MODULE_NAME}"; then
        warn "excalibur module is already loaded."
        ask "Reinstall / upgrade the kernel driver?" && INSTALL_DRIVER=true || INSTALL_DRIVER=false
    else
        ask "Install the excalibur-wmi kernel driver?" && INSTALL_DRIVER=true || INSTALL_DRIVER=false
        [[ "$INSTALL_DRIVER" == false ]] && warn "Skipping driver — hardware controls will not work."
    fi

    # Control panel
    echo ""
    echo -e "  ${M}── Control Panel ─────────────────────────────────────────────${NC}"
    if ask "Install the Excalibur TUI control panel?"; then
        INSTALL_PANEL=true
        if check_textual; then
            INSTALL_TEXTUAL=false
        else
            warn "Textual is not installed."
            ask "Install Textual automatically?" && INSTALL_TEXTUAL=true || INSTALL_TEXTUAL=false
        fi
    else
        INSTALL_PANEL=false
        INSTALL_TEXTUAL=false
    fi

    # udev
    echo ""
    echo -e "  ${M}── Permissions ───────────────────────────────────────────────${NC}"
    echo -e "  ${D}udev rules let you run the control panel without sudo.${NC}"
    ask "Install udev rules (recommended)?" && INSTALL_UDEV=true || INSTALL_UDEV=false
    [[ "$INSTALL_UDEV" == false ]] && warn "You will need sudo to run the control panel."

    # Desktop
    echo ""
    echo -e "  ${M}── Desktop Integration ───────────────────────────────────────${NC}"
    ask "Install a desktop entry (adds the app to your launcher)?" \
        && INSTALL_DESKTOP=true || INSTALL_DESKTOP=false

    # Summary
    echo ""
    echo -e "  ${M}── Summary ────────────────────────────────────────────────────${NC}"
    divider
    [[ "$INSTALL_DRIVER"  == true ]] && info "  ✦ Kernel driver" || info "  ○ Kernel driver (skip)"
    [[ "$INSTALL_TEXTUAL" == true ]] && info "  ✦ Textual library" || info "  ○ Textual (skip)"
    [[ "$INSTALL_PANEL"   == true ]] && info "  ✦ Control panel  →  ${CONTROL_PANEL_BIN}" || info "  ○ Control panel (skip)"
    [[ "$INSTALL_UDEV"    == true ]] && info "  ✦ udev rules (no-sudo access)" || info "  ○ udev rules (skip)"
    [[ "$INSTALL_DESKTOP" == true ]] && info "  ✦ Desktop entry" || info "  ○ Desktop entry (skip)"
    divider

    if ! ask "Proceed with installation?"; then
        echo -e "\n  ${Y}Cancelled.${NC}\n"
        exit 0
    fi

    echo ""
    [[ "$INSTALL_DRIVER"  == true ]] && { build_driver; install_driver; }
    [[ "$INSTALL_TEXTUAL" == true ]] && install_textual
    [[ "$INSTALL_PANEL"   == true ]] && install_control_panel
    [[ "$INSTALL_UDEV"    == true ]] && install_udev_rules
    [[ "$INSTALL_DESKTOP" == true ]] && install_desktop_entry

    verify_install

    echo ""
    echo -e "  ${G}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${G}║${NC}  ${W}✦  Excalibur installation complete!  ✦${NC}               ${G}║${NC}"
    echo -e "  ${G}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${W}Launch the control panel:${NC}"
    if [[ "$INSTALL_UDEV" == true ]]; then
        echo -e "    ${C}excalibur-panel${NC}     ${D}(no sudo needed after re-login)${NC}"
    else
        echo -e "    ${C}sudo excalibur-panel${NC}"
    fi
    echo ""
    echo -e "  ${D}Reload driver if needed:  sudo modprobe excalibur${NC}"
    echo -e "  ${D}Check driver status:      sudo dmesg | grep excalibur${NC}"
    echo ""
}

interactive_uninstall() {
    print_banner
    echo -e "  ${R}Uninstall mode${NC}\n"
    ask "Remove the kernel driver?"    && uninstall_driver        || true
    ask "Remove the control panel?"    && uninstall_control_panel || true
    ask "Remove udev rules?"           && uninstall_udev_rules    || true
    echo -e "\n  ${G}✔${NC}  Uninstall complete.\n"
}

# ── Entry point ───────────────────────────────────────────────────────────────
require_root
detect_distro
detect_compiler

case "${1:-}" in
    install)
        print_banner
        step "Non-interactive install"
        check_build_tools    || exit 1
        check_kernel_headers || exit 1
        check_python         || exit 1
        check_textual        || install_textual
        build_driver
        install_driver
        install_control_panel
        install_udev_rules
        install_desktop_entry
        verify_install
        ok "All done. Run: excalibur-panel"
        ;;
    uninstall)
        print_banner
        uninstall_driver
        uninstall_control_panel
        uninstall_udev_rules
        ok "Uninstall complete."
        ;;
    "")
        interactive_install
        ;;
    *)
        echo -e "Usage: sudo $0 [install|uninstall]"
        exit 1
        ;;
esac
