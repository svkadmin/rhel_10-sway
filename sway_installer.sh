#!/bin/bash

# ==============================================================================
# Sway Tiling WM - Build from Source Script for Red Hat Enterprise Linux 10
# ==============================================================================
#
# --- Variables ---
if [ "$SUDO_USER" ]; then
    CURRENT_USER=$SUDO_USER
else
    echo "This script must be run with sudo."
    exit 1
fi
USER_HOME=$(getent passwd "$CURRENT_USER" | cut -d: -f6)
SWAY_CONFIG_DIR="$USER_HOME/.config/sway"
BUILD_DIR="/tmp/sway-build"

# --- Functions ---

print_header() {
    echo "=============================================================================="
    echo "$1"
    echo "=============================================================================="
}

check_success() {
    if [ $? -ne 0 ]; then
        echo "Error: The previous command failed. Aborting."
        exit 1
    fi
}

# --- Main Script ---

if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi

print_header "Step 1: Enabling Required Repositories & Tools"

echo "--> Enabling the CodeReady Linux Builder (CRB) repository..."
subscription-manager repos --enable codeready-builder-for-rhel-10-$(arch)-rpms
check_success

if ! rpm -q epel-release &>/dev/null; then
    echo "--> Installing the EPEL repository..."
    dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm
    check_success
else
    echo "--> EPEL repository is already installed. Skipping."
fi

if ! dnf group list --installed 'Development Tools' &>/dev/null; then
    echo "--> Installing 'Development Tools' group..."
    dnf groupinstall -y 'Development Tools'
    check_success
else
    echo "--> 'Development Tools' group is already installed. Skipping."
fi

echo "--> Syncing repositories..."
dnf update -y
check_success

print_header "Step 2: Installing Build Dependencies"

# Install build dependencies
BUILD_DEPS=(
    git gcc cmake meson ninja-build wayland-devel wayland-protocols-devel
    libinput-devel libxkbcommon-devel xorg-x11-server-Xwayland-devel
    systemd-devel libdrm-devel mesa-libgbm-devel mesa-libEGL-devel
    vulkan-devel libdisplay-info-devel pango-devel cairo-devel
    gdk-pixbuf2-devel json-c-devel pcre2-devel scdoc libevdev-devel
    hwdata-devel glslang libseat-devel hwdata xcb-util-renderutil-devel
    xcb-util-wm-devel xcb-util-errors-devel lcms2-devel fish pam-devel
    libpcap-devel expat-devel
)
echo "--> Installing build dependencies..."
dnf install -y "${BUILD_DEPS[@]}"
check_success

print_header "Step 3: Cloning and Building Sway with Subprojects"

echo "--> Ensuring build directory exists at $BUILD_DIR"
# Clean up previous build attempts
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
check_success

echo "--> Cloning Sway repository (version 1.10)..."
git clone --branch 1.10 https://github.com/swaywm/sway.git
check_success
cd sway
check_success

echo "--> Creating subprojects directory..."
mkdir -p subprojects
check_success

echo "--> Cloning wlroots and other dependencies as subprojects..."
git clone --branch 0.18.2 https://gitlab.freedesktop.org/wlroots/wlroots.git subprojects/wlroots
check_success
git clone https://gitlab.freedesktop.org/wayland/wayland.git subprojects/wayland
check_success
git clone https://gitlab.freedesktop.org/wayland/wayland-protocols.git subprojects/wayland-protocols
check_success
git clone https://gitlab.freedesktop.org/emersion/libdisplay-info.git subprojects/libdisplay-info
check_success
git clone https://gitlab.freedesktop.org/emersion/libliftoff.git subprojects/libliftoff
check_success
git clone https://gitlab.freedesktop.org/mesa/drm.git subprojects/libdrm
check_success
git clone https://git.sr.ht/~kennylevinsen/seatd subprojects/seatd
check_success

echo "--> Configuring Sway and all subprojects..."
meson setup build -Dprefix=/usr/local
check_success

echo "--> Compiling and installing Sway and all subprojects..."
ninja -C build install
check_success

print_header "Step 4: Installing Available Essential Tools"

# Install tools that are available in the repositories.
# Other tools like alacritty, waybar, etc., must be built from source.
AVAILABLE_TOOLS=(
    xorg-x11-server-Xwayland # For running X11 apps on Wayland
    wl-clipboard  # Command-line copy/paste for Wayland
    pipewire      # For audio and screen sharing
    wireplumber   # Session manager for PipeWire
    pavucontrol   # PulseAudio volume control (works with PipeWire)
    fontawesome-fonts # Icons for status bars and other tools
)

echo "--> Installing available tools..."
dnf install -y "${AVAILABLE_TOOLS[@]}"
check_success

print_header "Step 5: Creating Default Sway Configuration"

if [ -d "$SWAY_CONFIG_DIR" ]; then
    echo "--> Sway configuration directory already exists at $SWAY_CONFIG_DIR. Skipping creation."
else
    echo "--> Creating Sway configuration directory at $SWAY_CONFIG_DIR..."
    runuser -u $CURRENT_USER -- mkdir -p "$SWAY_CONFIG_DIR"
    check_success

    echo "--> Copying the default Sway configuration file..."
    # Sway installation from source places the config in /usr/local/etc/sway
    if [ -f "/usr/local/etc/sway/config" ]; then
        runuser -u $CURRENT_USER -- cp /usr/local/etc/sway/config "$SWAY_CONFIG_DIR/config"
        check_success
        echo "--> Default Sway configuration has been created at $SWAY_CONFIG_DIR/config"
        echo "    You can now edit this file to customize your Sway setup."
    else
        echo "--> WARNING: Default config template not found at /usr/local/etc/sway/config."
        echo "    You may need to create a configuration file manually at $SWAY_CONFIG_DIR/config"
        echo "    You can find a sample here: https://github.com/swaywm/sway/blob/master/config.in"
    fi
fi

# Set ownership of the .config directory to the user, just in case
chown -R $CURRENT_USER:$CURRENT_USER "$USER_HOME/.config"
check_success

print_header "Step 6: Updating Library Cache and Creating Links"

# Create a config file to tell the dynamic linker to look in /usr/local/lib64
echo "--> Configuring dynamic linker..."
echo "/usr/local/lib64" > /etc/ld.so.conf.d/local.conf
check_success

# Update the shared library cache to apply the new configuration
echo "--> Updating shared library cache..."
ldconfig
check_success

# Create symbolic links in /usr/bin so the commands are found in the default PATH
echo "--> Creating symbolic links for sway, swaybar, and swaylock..."
ln -sf /usr/local/bin/sway /usr/bin/sway
check_success
ln -sf /usr/local/bin/swaybar /usr/bin/swaybar
check_success
ln -sf /usr/local/bin/swaylock /usr/bin/swaylock
check_success


print_header "Installation Complete!"

echo ""
echo "What's next?"
echo "------------"
echo "1. IMPORTANT: Reboot your system to ensure all services and paths are correctly loaded."
echo "2. At the login screen, click the gear icon (or similar) and select 'Sway' from the list of sessions."
echo "   (The build process should have installed a session file in /usr/local/share/wayland-sessions/)"
echo "3. Log in, and you should be greeted with the Sway desktop."
echo ""
echo "Building Other Tools:"
echo "---------------------"
echo "This script only installed Sway. Many essential UI tools also need to be built from source."
echo "You will likely want a terminal, application launcher, and status bar."
echo "  - Terminal: Alacritty (https://github.com/alacritty/alacritty)"
echo "  - Status Bar: Waybar (https://github.com/Alexays/Waybar)"
echo "  - App Launcher: Rofi (Wayland forks exist, e.g., https://github.com/lbonn/rofi)"
echo "  - Screenshots: grim + slurp (https://github.com/emersion/grim)"
echo "The build process for these is often similar: install dependencies, clone, meson/ninja build, install."
echo ""
echo "Important Notes:"
echo "----------------"
echo "- SELinux: RHEL uses SELinux, which may require additional configuration. If you encounter permission issues, you may need to investigate SELinux policies."
echo "- Configuration: The default Sway config is very basic. You will need to edit '$SWAY_CONFIG_DIR/config' to set a terminal, application launcher, keybindings, etc."

echo ""
