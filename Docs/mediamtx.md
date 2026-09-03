# MediaMTX Management & Setup

## Quick Automated Setup & Check
Run the automated script to check status, install, start MediaMTX server, and get your connection URL:

```bash
./setup_mediamtx.sh
```

---

## Manual Installation Guide

1. Download MediaMTX
```bash
cd /tmp
wget https://github.com/bluenviron/mediamtx/releases/download/v1.20.1/mediamtx_v1.20.1_linux_amd64.tar.gz
tar -xzf mediamtx_v1.20.1_linux_amd64.tar.gz
sudo mv mediamtx /usr/local/bin/
sudo mkdir -p /usr/local/etc
sudo mv mediamtx.yml /usr/local/etc/
mediamtx --version
```

2. Test MediaMTX manually
```bash
mediamtx /usr/local/etc/mediamtx.yml
```

3. Make it a system service
```bash
sudo tee /etc/systemd/system/mediamtx.service >/dev/null <<'EOF'
[Unit]
Description=MediaMTX RTSP / WebRTC Server
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
```

4. Configuration for FPV / Gazebo Stream
Edit `/usr/local/etc/mediamtx.yml`:
```yaml
paths:
  all_others:

  fpv_stream:
    source: publisher
```

Restart service:
```bash
sudo systemctl restart mediamtx
```

Test Stream Connection:
```bash
ffplay rtsp://<SYSTEM_IP>:8554/fpv_stream
```