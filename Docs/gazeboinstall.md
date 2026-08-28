lsb_release -a
gz sim --version
which gz
dpkg -l | grep -E 'gz-sim|gazebo'


1. Remove the incorrect key file

sudo rm -f /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg

Step 1 — Add the Gazebo package repository
sudo apt update
sudo apt install -y curl lsb-release gnupg
Add the repository:
sudo curl -fsSL https://packages.osrfoundation.org/gazebo.gpg \
  -o /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg

sudo apt update
sudo apt install -y gz-harmonic


Step 1 — Install plugin build dependencies

Run:

sudo apt install -y \
    git \
    cmake \
    build-essential \
    libgz-sim8-dev \
    rapidjson-dev \
    libopencv-dev \
    libyaml-cpp-dev
    
    GSTREAMER CAN BE MAKE ERROR WE HAVE TO INSTALL THE PACKAGE SEPRATE 
    sudo apt update
sudo apt install -y \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev

also the plugin for gstreamer+
sudo apt update
sudo apt install -y gstreamer1.0-plugins-bad


cd ~
git clone https://github.com/ArduPilot/ardupilot_gazebo.git


cd ~/ardupilot_gazebo

mkdir -p build

cd build

cmake ..
make -j$(nproc)

1. Add Gazebo plugin paths
echo 'export GZ_SIM_SYSTEM_PLUGIN_PATH=$HOME/ardupilot_gazebo/build:${GZ_SIM_SYSTEM_PLUGIN_PATH}' >> ~/.bashrc

echo 'export GZ_SIM_RESOURCE_PATH=$HOME/ardupilot_gazebo/models:$HOME/ardupilot_gazebo/worlds:${GZ_SIM_RESOURCE_PATH}' >> ~/.bashrc



source ~/.bashrc
gz sim -v4 -r ~/ardupilot_gazebo/worlds/zephyr_runway.sdf

cd ~/ardupilot
python3 Tools/autotest/sim_vehicle.py \
    -v ArduPlane \
    -f gazebo-zephyr \
    --model JSON \
    --console \
    --map
