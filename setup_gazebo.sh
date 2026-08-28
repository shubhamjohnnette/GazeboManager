#!/bin/bash
set -e

echo "================================"
echo "Starting Gazebo & ardupilot_gazebo Setup"
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

# 2. Install Build Dependencies
echo "[2/4] Installing plugin build dependencies..."
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
    gstreamer1.0-plugins-bad

# 3. Clone & Build ardupilot_gazebo
echo "[3/4] Cloning and building ardupilot_gazebo..."
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

# 4. Configure ~/.bashrc
echo "[4/4] Configuring ~/.bashrc environment variables..."
BASHRC="$HOME/.bashrc"
sed -i '/GZ_SIM_SYSTEM_PLUGIN_PATH/d' "$BASHRC" 2>/dev/null
sed -i '/GZ_SIM_RESOURCE_PATH/d' "$BASHRC" 2>/dev/null

echo "export GZ_SIM_SYSTEM_PLUGIN_PATH=$TARGET_DIR/build:\$GZ_SIM_SYSTEM_PLUGIN_PATH" >> "$BASHRC"
echo "export GZ_SIM_RESOURCE_PATH=$TARGET_DIR/models:$TARGET_DIR/worlds:\$GZ_SIM_RESOURCE_PATH" >> "$BASHRC"

export GZ_SIM_SYSTEM_PLUGIN_PATH="$TARGET_DIR/build:$GZ_SIM_SYSTEM_PLUGIN_PATH"
export GZ_SIM_RESOURCE_PATH="$TARGET_DIR/models:$TARGET_DIR/worlds:$GZ_SIM_RESOURCE_PATH"

echo "================================"
echo "[SUCCESS] Gazebo & ardupilot_gazebo setup completed!"
echo "================================"
