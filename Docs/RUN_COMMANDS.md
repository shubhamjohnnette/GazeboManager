
export GZ_SIM_SYSTEM_PLUGIN_PATH=$HOME/ardupilot_gazebo/build:$GZ_SIM_SYSTEM_PLUGIN_PATH
export GZ_SIM_RESOURCE_PATH=$HOME/ardupilot_gazebo/models:$HOME/ardupilot_gazebo/worlds:$GZ_SIM_RESOURCE_PATH

gz sim -v4 -r zephyr_gimbal_runway.sdf


# 2. Launch Gazebo with upright Zephyr Gimbal world
gz sim -v4 -r zephyr_gimbal_runway.sdf

# 3. Launch ArduPlane SITL
cd ~/ardupilot
python3 Tools/autotest/sim_vehicle.py  -v ArduPlane -f gazebo-zephyr --model JSON --add-param-file=$HOME/ardupilot_gazebo/config/gazebo-zephyr-gimbal.parm --console --map



Step 1: Enable Video Streaming in Gazebo
While Gazebo (zephyr_gimbal_runway.sdf) is running, execute this command in a new terminal to turn on the camera's GStreamer UDP pipeline:

gz topic -t /gimbal/camera/enable_streaming -m gz.msgs.Boolean -p "data: 1"

bash
gz topic -t /world/zephyr_runway/model/zephyr_with_gimbal/model/gimbal/link/pitch_link/sensor/camera/image/enable_streaming -m gz.msgs.Boolean -p "data: 1"


# Replace 192.168.1.255 with your network subnet broadcast address
socat UDP4-LISTEN:5600,reuseaddr,fork UDP4-DATAGRAM:192.168.1.255:5600,broadcast


Receiving Video on the Target Device
On the target device (phone/tablet/laptop connected to the same network):

In QGroundControl: Go to Settings -> Video -> Source: UDP h.264 Video Stream -> Port: 5600.
In VLC / FFplay: Open network stream udp://@:5600.


ffplay -flags low_delay -fflags nobuffer udp://127.0.0.1:5600
gz topic -t /gimbal/camera/enable_streaming -m gz.msgs.Boolean -p "data: 1"

tpl-u-2204@jtplu2204-ThinkStation-P350:~/ardupilot_gazebo$ gz topic -t /gimbal/camera/enable_streaming -m gz.msgs.Boolean -p "data: 1"
jtpl-u-2204@jtplu2204-ThinkStation-P350:~/ardupilot_gazebo$ 

ffplay -flags low_delay -fflags nobuffer -f mpegts udp://127.0.0.1:5600


sudo apt update
sudo apt install -y gstreamer1.0-plugins-bad
 