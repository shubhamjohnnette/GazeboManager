#!/bin/bash
# MediaMTX Management and Setup Script
# Checks MediaMTX status, installs MediaMTX if missing, starts/restarts the server in a NEW terminal,
# and displays system IP & RTSP stream connection details (IP:8554/fpv_stream).

set -e

# Helper function to check if running in WSL
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

# Helper function to setup GUI DISPLAY for WSL
setup_wsl_gui_env() {
    if is_wsl; then
        if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
            local host_ip
            host_ip=$(ip route show default 2>/dev/null | awk '{print $3}')
            if [ -n "$host_ip" ]; then
                export DISPLAY="${host_ip}:0"
            else
                export DISPLAY=":0"
            fi
        fi
        export MESA_GL_VERSION_OVERRIDE=3.3
        export LIBGL_ALWAYS_INDIRECT=0
    fi
}

# Helper function to launch a command in a new terminal window
launch_in_new_terminal() {
    local cmd="$1"
    local title="${2:-MediaMTX RTSP Server}"
    local tmp_script="/tmp/launch_mediamtx_$$.sh"

    cat << EOF > "$tmp_script"
#!/bin/bash
$cmd
exec bash
EOF
    chmod +x "$tmp_script"

    if is_wsl; then
        setup_wsl_gui_env
        local distro_flag=""
        if [ -n "$WSL_DISTRO_NAME" ]; then
            distro_flag="-d $WSL_DISTRO_NAME"
        fi

        if command -v wt.exe &>/dev/null; then
            wt.exe --title "$title" wsl.exe $distro_flag bash "$tmp_script" &
            return 0
        elif command -v cmd.exe &>/dev/null; then
            cmd.exe /c start "$title" wsl.exe $distro_flag bash "$tmp_script" &
            return 0
        elif command -v powershell.exe &>/dev/null; then
            powershell.exe -Command "Start-Process wsl.exe -ArgumentList '$distro_flag bash \"$tmp_script\"'" &
            return 0
        fi
    fi

    if command -v gnome-terminal &>/dev/null; then
        gnome-terminal --title="$title" -- bash "$tmp_script" &
    elif command -v xfce4-terminal &>/dev/null; then
        xfce4-terminal --title="$title" -e "bash \"$tmp_script\"" &
    elif command -v konsole &>/dev/null; then
        konsole --title="$title" -e bash "$tmp_script" &
    elif command -v xterm &>/dev/null; then
        xterm -T "$title" -e "bash \"$tmp_script\"" &
    else
        echo "[WARNING] Terminal emulator not detected. Launching in current terminal..."
        bash "$tmp_script"
    fi
}

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Helper function to get current system IP address
get_system_ip() {
    local sys_ip
    sys_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$sys_ip" ]; then
        sys_ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+')
    fi
    if [ -z "$sys_ip" ]; then
        sys_ip="127.0.0.1"
    fi
    echo "$sys_ip"
}

# Helper function to check if MediaMTX process is active
is_mediamtx_running() {
    if pgrep -x mediamtx >/dev/null 2>&1 || pgrep -f "/usr/local/bin/mediamtx" >/dev/null 2>&1; then
        return 0
    elif systemctl is-active --quiet mediamtx 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Helper function to check if MediaMTX binary is installed
is_mediamtx_installed() {
    if command -v mediamtx >/dev/null 2>&1 || [ -x "/usr/local/bin/mediamtx" ]; then
        return 0
    else
        return 1
    fi
}

# Install MediaMTX binary, configuration, and systemd service
install_mediamtx() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}       Installing MediaMTX Server      ${NC}"
    echo -e "${BLUE}========================================${NC}"

    # Detect Architecture
    ARCH_RAW=$(uname -m)
    case "$ARCH_RAW" in
        x86_64)  ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64v8" ;;
        armv7l)  ARCH="armv7" ;;
        *)
            echo -e "${RED}[ERROR] Unsupported architecture: $ARCH_RAW${NC}"
            exit 1
            ;;
    esac

    VERSION="v1.20.1"
    TAR_NAME="mediamtx_${VERSION}_linux_${ARCH}.tar.gz"
    DOWNLOAD_URL="https://github.com/bluenviron/mediamtx/releases/download/${VERSION}/${TAR_NAME}"
    TMP_DIR="/tmp/mediamtx_install"

    echo -e "${CYAN}[1/4] Downloading MediaMTX ${VERSION} (${ARCH})...${NC}"
    mkdir -p "$TMP_DIR"
    curl -L "$DOWNLOAD_URL" -o "$TMP_DIR/$TAR_NAME"

    echo -e "${CYAN}[2/4] Extracting and installing binary to /usr/local/bin/...${NC}"
    tar -xzf "$TMP_DIR/$TAR_NAME" -C "$TMP_DIR"
    sudo mv "$TMP_DIR/mediamtx" /usr/local/bin/
    sudo chmod +x /usr/local/bin/mediamtx

    echo -e "${CYAN}[3/4] Setting up configuration in /usr/local/etc/...${NC}"
    sudo mkdir -p /usr/local/etc
    if [ ! -f /usr/local/etc/mediamtx.yml ]; then
        if [ -f "$TMP_DIR/mediamtx.yml" ]; then
            sudo mv "$TMP_DIR/mediamtx.yml" /usr/local/etc/
        else
            sudo tee /usr/local/etc/mediamtx.yml >/dev/null <<'EOF'
# MediaMTX Configuration File

paths:
  all_others:

  fpv_stream:
    source: publisher

EOF
        fi
    fi

    # Cleanup temp directory
    rm -rf "$TMP_DIR"

    echo -e "${CYAN}[4/4] Creating systemd service...${NC}"
    sudo tee /etc/systemd/system/mediamtx.service >/dev/null <<'EOF'
[Unit]
Description=MediaMTX RTSP / WebRTC Server
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/mediamtx /usr/local/etc/mediamtx.yml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable mediamtx

    echo -e "${GREEN}[SUCCESS] MediaMTX installation completed successfully!${NC}"
}

# Print system connection details
show_connection_info() {
    SYS_IP=$(get_system_ip)
    RTSP_PORT="8554"
    STREAM_PATH="fpv_stream"
    RTSP_URL="rtsp://${SYS_IP}:${RTSP_PORT}/${STREAM_PATH}"
    WEBRTC_URL="http://${SYS_IP}:8889/${STREAM_PATH}"

    echo ""
    echo -e "${GREEN}=====================================================${NC}"
    echo -e "${GREEN}        MediaMTX Server Status: RUNNING             ${NC}"
    echo -e "${GREEN}=====================================================${NC}"
    echo -e " Current System IP : ${CYAN}${SYS_IP}${NC}"
    echo -e " RTSP Port         : ${CYAN}${RTSP_PORT}${NC}"
    echo -e " Stream Name       : ${CYAN}${STREAM_PATH}${NC}"
    echo -e " Full RTSP URL     : ${YELLOW}${RTSP_URL}${NC}"
    echo -e " WebRTC Player URL : ${CYAN}${WEBRTC_URL}${NC}"
    echo -e "${GREEN}=====================================================${NC}"
    echo -e "${CYAN}Connection Commands:${NC}"
    echo -e "  • FFplay Client  : ${YELLOW}ffplay ${RTSP_URL}${NC}"
    echo -e "  • VLC Client     : ${YELLOW}vlc ${RTSP_URL}${NC}"
    echo -e "  • GStreamer Push : ${YELLOW}gst-launch-1.0 ... ! rtspclientsink location=${RTSP_URL}${NC}"
    echo -e "${GREEN}=====================================================${NC}"
}

# Stop MediaMTX server
stop_mediamtx() {
    echo -e "${YELLOW}[INFO] Stopping MediaMTX server...${NC}"
    sudo systemctl stop mediamtx 2>/dev/null || true
    sudo pkill -x mediamtx 2>/dev/null || true
    sleep 1
    echo -e "${GREEN}[SUCCESS] MediaMTX server stopped.${NC}"
}

# Start MediaMTX in a NEW terminal window with connection info banner & live logs
start_in_new_terminal() {
    if ! is_mediamtx_installed; then
        echo -e "${RED}[WARNING] MediaMTX is not installed.${NC}"
        read -p "Would you like to download & install MediaMTX now? [Y/n]: " INS_ANS
        if [[ ! "$INS_ANS" =~ ^[Nn]$ ]]; then
            install_mediamtx
        else
            echo "[ABORT] Installation cancelled."
            return 1
        fi
    fi

    # Stop any background service first to avoid port conflict
    sudo systemctl stop mediamtx 2>/dev/null || true
    sudo pkill -x mediamtx 2>/dev/null || true
    sleep 1

    local run_cmd='
SYS_IP=$(hostname -I 2>/dev/null | awk "{print \$1}")
[ -z "$SYS_IP" ] && SYS_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP "src \K\S+")
[ -z "$SYS_IP" ] && SYS_IP="127.0.0.1"

echo -e "\033[0;32m=====================================================\033[0m"
echo -e "\033[0;32m        MediaMTX RTSP Server & Live Output           \033[0m"
echo -e "\033[0;32m=====================================================\033[0m"
echo -e " Current System IP : \033[0;36m$SYS_IP\033[0m"
echo -e " RTSP Port         : \033[0;36m8554\033[0m"
echo -e " Stream Name       : \033[0;36mfpv_stream\033[0m"
echo -e " Full RTSP URL     : \033[1;33mrtsp://$SYS_IP:8554/fpv_stream\033[0m"
echo -e " WebRTC Player URL : \033[0;36mhttp://$SYS_IP:8889/fpv_stream\033[0m"
echo -e "\033[0;32m=====================================================\033[0m"
echo -e " Connection Commands:"
echo -e "   • FFplay Client  : \033[1;33mffplay rtsp://$SYS_IP:8554/fpv_stream\033[0m"
echo -e "   • VLC Client     : \033[1;33mvlc rtsp://$SYS_IP:8554/fpv_stream\033[0m"
echo -e "\033[0;32m=====================================================\033[0m"
echo "Starting MediaMTX server process..."
echo ""
/usr/local/bin/mediamtx /usr/local/etc/mediamtx.yml
'

    echo -e "${GREEN}Launching MediaMTX in a new terminal window...${NC}"
    launch_in_new_terminal "$run_cmd" "MediaMTX RTSP Server"
}

# Restart MediaMTX in a NEW terminal window
restart_in_new_terminal() {
    echo -e "${YELLOW}[INFO] Restarting MediaMTX server...${NC}"
    stop_mediamtx
    start_in_new_terminal
}

# Interactive Menu
show_mediamtx_menu() {
    while true; do
        echo ""
        echo -e "${BLUE}=====================================================${NC}"
        echo -e "${BLUE}             MediaMTX Server Manager                ${NC}"
        echo -e "${BLUE}=====================================================${NC}"
        if is_mediamtx_running; then
            echo -e " Status: ${GREEN}RUNNING${NC}"
        else
            echo -e " Status: ${RED}STOPPED${NC}"
        fi
        echo -e "${BLUE}=====================================================${NC}"
        echo "  1) Start MediaMTX Server (opens in new terminal with IP & info)"
        echo "  2) Restart MediaMTX Server (opens in new terminal with IP & info)"
        echo "  3) Check MediaMTX Status & Connection Info"
        echo "  4) Stop MediaMTX Server"
        echo "  5) Download / Install MediaMTX"
        echo "  0) Exit / Back"
        echo -e "${BLUE}=====================================================${NC}"
        read -p "Select option [0-5]: " MENU_CHOICE

        case "$MENU_CHOICE" in
            1)
                start_in_new_terminal
                ;;
            2)
                restart_in_new_terminal
                ;;
            3)
                if is_mediamtx_running; then
                    show_connection_info
                else
                    echo -e "${RED}[STATUS] MediaMTX server is NOT running.${NC}"
                fi
                ;;
            4)
                stop_mediamtx
                ;;
            5)
                install_mediamtx
                ;;
            0)
                echo "Exiting MediaMTX Manager."
                break
                ;;
            *)
                echo "Invalid option. Please enter 0, 1, 2, 3, 4, or 5."
                ;;
        esac
    done
}

# --- CLI Arguments Handler ---
if [[ "$1" == "--start" ]]; then
    start_in_new_terminal
    exit 0
elif [[ "$1" == "--restart" ]]; then
    restart_in_new_terminal
    exit 0
elif [[ "$1" == "--status" ]]; then
    if is_mediamtx_running; then
        show_connection_info
    else
        echo -e "${RED}[STATUS] MediaMTX server is NOT running.${NC}"
    fi
    exit 0
elif [[ "$1" == "--stop" ]]; then
    stop_mediamtx
    exit 0
elif [[ "$1" == "-y" ]] || [[ "$1" == "--yes" ]]; then
    if ! is_mediamtx_installed; then
        install_mediamtx
    fi
    start_in_new_terminal
    exit 0
fi

# Default: Show Interactive Menu
show_mediamtx_menu
