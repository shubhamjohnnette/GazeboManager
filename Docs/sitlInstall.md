sudo apt install -y git python3 python3-pip python3-venv build-essential


cd ~
git clone https://github.com/ArduPilot/ardupilot.git
cd ~/ardupilot

git submodule update --init --recursive

cd ~/ardupilot
Tools/environment_install/install-prereqs-ubuntu.sh -y

source ~/.profile

cd ~/ardupilot
./waf configure --board sitl

./waf plane


python3 Tools/autotest/sim_vehicle.py -v ArduPlane --console --map