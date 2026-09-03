1. Install MediaMTX

2. Download MediaMTX
cd /tmp

wget https://github.com/bluenviron/mediamtx/releases/download/v1.20.1/mediamtx_v1.20.1_linux_amd64.tar.gz

tar -xzf mediamtx_v1.20.1_linux_amd64.tar.gz

sudo mv mediamtx /usr/local/bin/
sudo mkdir -p /usr/local/etc
sudo mv mediamtx.yml /usr/local/etc/

mediamtx --version


4. Test MediaMTX manually
mediamtx /usr/local/etc/mediamtx.yml

5. Make it a system service

sudo tee /etc/systemd/system/mediamtx.service >/dev/null <<'EOF'
[Unit]
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/mediamtx /usr/local/etc/mediamtx.yml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable mediamtx
sudo systemctl start mediamtx

2. Most likely configuration: MPEG-TS over UDP

If your Gazebo GStreamer pipeline is producing MPEG-TS, MediaMTX can directly consume it. The official configuration is udp+mpegts://....

Edit:

sudo nano /usr/local/etc/mediamtx.yml
Find the paths: section. You can use:
remeber yaml indentation matter 

paths:
  gazebo:
    source: udp+mpegts://127.0.0.1:5600

Restart

sudo systemctl restart mediamtx

Test
ffplay rtsp://127.0.0.1:8554/gazebo