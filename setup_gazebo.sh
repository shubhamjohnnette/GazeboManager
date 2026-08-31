#!/bin/bash
set -e

# Helper function to check if running in WSL (Windows Subsystem for Linux)
is_wsl() {
    if [ -n "$WSL_DISTRO_NAME" ] || [ -n "$WSL_INTEROP" ]; then
        return 0
    elif [ -f /proc/version ] && grep -qi "microsoft" /proc/version; then
        return 0
    elif [ -f /proc/sys/kernel/osrelease ] && grep -qi "microsoft" /proc/sys/kernel/osrelease; then
        return 0
    fi
    return 1
}

echo "================================"
echo "Starting Gazebo & ardupilot_gazebo Setup"
if is_wsl; then
    echo "Environment: WSL (Windows Subsystem for Linux) detected"
else
    echo "Environment: Native Linux detected"
fi
echo "================================"

# 1. Add Gazebo Package Repository & Install Gazebo Harmonic
echo "[1/4] Installing Gazebo Harmonic repository & packages..."
sudo apt update
sudo apt install -y curl lsb-release gnupg

# Add Keyring and Repository
sudo rm -f /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg 2>/dev/null || true
sudo curl -fsSL https://packages.osrfoundation.org/gazebo.gpg -o /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] http://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/gazebo-stable.list > /dev/null

sudo apt update
sudo apt install -y gz-harmonic

# 2. Install Build Dependencies & WSL GUI Tools
echo "[2/4] Installing plugin build dependencies & GUI tools..."
sudo apt install -y \
    git \
    cmake \
    build-essential \
    libgz-sim8-dev \
    rapidjson-dev \
    libopencv-dev \
    libyaml-cpp-dev \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    gstreamer1.0-plugins-bad \
    mesa-utils \
    x11-utils \
    python3-pip \
    python3-wxgtk4.0 \
    socat

# 3. Clone & Build ardupilot_gazebo
echo "[3/5] Cloning and building ardupilot_gazebo..."
TARGET_DIR="$HOME/ardupilot_gazebo"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Cloning ardupilot_gazebo to $TARGET_DIR..."
    git clone https://github.com/shubhamjohnnette/ardupilot_gazebo.git "$TARGET_DIR"
else
    echo "Directory $TARGET_DIR already exists."
fi

cd "$TARGET_DIR"
mkdir -p build
cd build
cmake ..
make -j$(nproc)

# 4. Clone Official ArduPilot SITL_Models Repository
echo "[4/5] Checking official ArduPilot SITL_Models repository..."
SITL_MODELS_DIR="$HOME/SITL_Models"
if [ ! -d "$SITL_MODELS_DIR" ]; then
    read -p "Would you like to clone official ArduPilot SITL_Models repository (~/SITL_Models)? [Y/n]: " CLONE_SITL
    if [[ ! "$CLONE_SITL" =~ ^[Nn]$ ]]; then
        echo "Cloning SITL_Models to $SITL_MODELS_DIR..."
        git clone https://github.com/ArduPilot/SITL_Models.git "$SITL_MODELS_DIR" || true
    fi
else
    echo "Official ArduPilot SITL_Models directory found at $SITL_MODELS_DIR."
fi

# 5. Configure ~/.bashrc
echo "[5/5] Configuring ~/.bashrc environment variables..."
BASHRC="$HOME/.bashrc"
sed -i '/GZ_SIM_SYSTEM_PLUGIN_PATH/d' "$BASHRC" 2>/dev/null
sed -i '/GZ_SIM_RESOURCE_PATH/d' "$BASHRC" 2>/dev/null

RES_PATH="$TARGET_DIR/models:$TARGET_DIR/worlds"
if [ -d "$SITL_MODELS_DIR/Gazebo" ]; then
    RES_PATH="$RES_PATH:$SITL_MODELS_DIR/Gazebo/models:$SITL_MODELS_DIR/Gazebo/worlds"
fi

echo "export GZ_SIM_SYSTEM_PLUGIN_PATH=$TARGET_DIR/build:\$GZ_SIM_SYSTEM_PLUGIN_PATH" >> "$BASHRC"
echo "export GZ_SIM_RESOURCE_PATH=$RES_PATH:\$GZ_SIM_RESOURCE_PATH" >> "$BASHRC"

export GZ_SIM_SYSTEM_PLUGIN_PATH="$TARGET_DIR/build:$GZ_SIM_SYSTEM_PLUGIN_PATH"
export GZ_SIM_RESOURCE_PATH="$RES_PATH:$GZ_SIM_RESOURCE_PATH"

if is_wsl; then
    echo "[WSL AUTO-CONFIG] Adding WSL GUI & OpenGL environment settings to ~/.bashrc..."
    sed -i '/WSL_DISPLAY_CONFIG/d' "$BASHRC" 2>/dev/null
    sed -i '/MESA_GL_VERSION_OVERRIDE/d' "$BASHRC" 2>/dev/null
    sed -i '/LIBGL_ALWAYS_INDIRECT/d' "$BASHRC" 2>/dev/null

    cat << 'EOF' >> "$BASHRC"
# WSL_DISPLAY_CONFIG: Automatic GUI display setup for WSL
if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
    export DISPLAY="$(ip route show default 2>/dev/null | awk '{print $3}'):0"
fi
export MESA_GL_VERSION_OVERRIDE=3.3
export LIBGL_ALWAYS_INDIRECT=0
EOF

    if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
        export DISPLAY="$(ip route show default 2>/dev/null | awk '{print $3}'):0"
    fi
    export MESA_GL_VERSION_OVERRIDE=3.3
    export LIBGL_ALWAYS_INDIRECT=0
fi

echo "================================"
echo "[SUCCESS] Gazebo & ardupilot_gazebo setup completed!"
echo "================================"
