#!/bin/bash

cd ~

BASHRC="$HOME/.bashrc"

# Helper function to expand ~, $HOME, and ${HOME} in path strings to full path (/home/username/...)
expand_path() {
    local path_str="$1"
    # Trim quotes and spaces
    path_str=$(echo "$path_str" | sed -E 's/^["'\''\t ]+|["'\''\t ]+$//g')
    # Replace ~ at start with $HOME
    path_str="${path_str/#\~/$HOME}"
    # Replace literal $HOME and ${HOME} with actual $HOME value
    path_str="${path_str//\$HOME/$HOME}"
    path_str="${path_str//\$\{HOME\}/$HOME}"
    echo "$path_str"
}

# Helper function to find a target directory in $HOME, $HOME/JSetup, or 1 child folder under $HOME
find_target_dir() {
    local target_name="$1"
    
    # 1. Direct child of $HOME (~/target_name)
    if [ -d "$HOME/$target_name" ]; then
        echo "$HOME/$target_name"
        return 0
    fi
    
    # 2. Check JSetup folder (~/JSetup/target_name)
    if [ -d "$HOME/JSetup/$target_name" ]; then
        echo "$HOME/JSetup/$target_name"
        return 0
    fi
    
    # 3. 1 child folder under $HOME (~/*/target_name)
    for sub in "$HOME"/*/; do
        [ -d "$sub" ] || continue
        local dir_path="${sub%/}"
        local base="${dir_path##*/}"
        # Skip hidden directories and JSetup (already checked)
        if [[ "$base" == .* || "$base" == "JSetup" ]]; then
            continue
        fi
        if [ -d "$dir_path/$target_name" ]; then
            echo "$dir_path/$target_name"
            return 0
        fi
    done
    
    return 1
}

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

# Helper function to setup GUI DISPLAY and OpenGL environment variables for WSL
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
            echo "[WSL INFO] DISPLAY variable automatically set to $DISPLAY for GUI support."
        fi

        # OpenGL compatibility settings for Gazebo (GZ Sim) & Mesa under WSL
        if [ -z "$MESA_GL_VERSION_OVERRIDE" ]; then
            export MESA_GL_VERSION_OVERRIDE=3.3
        fi
        export LIBGL_ALWAYS_INDIRECT=0
    fi
}

# Helper function to launch a command in a new terminal window
launch_in_new_terminal() {
    local cmd="$1"
    local title="${2:-Gazebo Simulation}"
    local tmp_script="/tmp/launch_gz_mgr_$$.sh"

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to run setup_gazebo.sh to install and configure Gazebo automatically
run_setup_gazebo() {
    local setup_script="$SCRIPT_DIR/setup_gazebo.sh"
    if [ ! -f "$setup_script" ]; then
        setup_script="$HOME/GazeboManager/setup_gazebo.sh"
    fi
    
    if [ -f "$setup_script" ]; then
        echo ""
        echo "================================"
        echo "Running Gazebo setup script ($setup_script)..."
        echo "================================"
        bash "$setup_script"
        
        GAZEBO_DIR="$HOME/ardupilot_gazebo"
        PLUGIN_OK=true
        RESOURCE_OK=true
    else
        echo "[ERROR] setup_gazebo.sh script not found at $setup_script."
    fi
}

# Function to download or update official ArduPilot SITL_Models
download_sitl_models() {
    echo "================================"
    echo "Downloading / Updating Official ArduPilot SITL_Models..."
    echo "================================"
    local target_dir="${SITL_MODELS_DIR:-$HOME/SITL_Models}"
    
    if [ ! -d "$target_dir" ]; then
        echo "Cloning official ArduPilot SITL_Models repository to $target_dir..."
        git clone https://github.com/ArduPilot/SITL_Models.git "$target_dir"
    else
        echo "Updating official ArduPilot SITL_Models repository at $target_dir..."
        git -C "$target_dir" pull
    fi
    
    SITL_MODELS_DIR="$target_dir"
    auto_fix_gazebo
    echo "================================"
    echo "[SUCCESS] Official ArduPilot SITL_Models repository updated successfully!"
    echo "================================"
}

# Function to automatically fix Gazebo environment variables in ~/.bashrc
auto_fix_gazebo() {
    if [ -n "$GAZEBO_DIR" ]; then
        echo "[AUTO-FIX] Updating ~/.bashrc with correct Gazebo paths..."
        sed -i '/GZ_SIM_SYSTEM_PLUGIN_PATH/d' "$BASHRC" 2>/dev/null
        sed -i '/GZ_SIM_RESOURCE_PATH/d' "$BASHRC" 2>/dev/null
        
        local res_path="$GAZEBO_DIR/models:$GAZEBO_DIR/worlds"
        if [ -n "$SITL_MODELS_DIR" ] && [ -d "$SITL_MODELS_DIR/Gazebo" ]; then
            res_path="$res_path:$SITL_MODELS_DIR/Gazebo/models:$SITL_MODELS_DIR/Gazebo/worlds"
        fi

        echo "export GZ_SIM_SYSTEM_PLUGIN_PATH=$GAZEBO_DIR/build:\$GZ_SIM_SYSTEM_PLUGIN_PATH" >> "$BASHRC"
        echo "export GZ_SIM_RESOURCE_PATH=$res_path:\$GZ_SIM_RESOURCE_PATH" >> "$BASHRC"
        export GZ_SIM_SYSTEM_PLUGIN_PATH="$GAZEBO_DIR/build:$GZ_SIM_SYSTEM_PLUGIN_PATH"
        export GZ_SIM_RESOURCE_PATH="$res_path:$GZ_SIM_RESOURCE_PATH"
        echo "[AUTO-FIX] ~/.bashrc updated and environment exported successfully!"
        PLUGIN_OK=true
        RESOURCE_OK=true
    else
        echo "[WARNING] ardupilot_gazebo directory not found on disk."
        echo "Please install ardupilot_gazebo by running git clone https://github.com/shubhamjohnnette/ardupilot_gazebo.git ~/ardupilot_gazebo"
        read -p "Would you like to automatically run setup_gazebo.sh to install & setup Gazebo on your system? [y/N]: " SETUP_ANS
        if [[ "$SETUP_ANS" =~ ^[Yy]$ ]]; then
            run_setup_gazebo
        fi
    fi
}

# Function to automatically setup and fix ArduPilot SITL
auto_fix_sitl() {
    echo "================================"
    echo "Starting Automatic SITL Setup & Fix..."
    echo "================================"
    
    local target_dir="${ARDUPILOT_DIR:-$HOME/ardupilot}"
    
    if [ ! -d "$target_dir" ]; then
        echo "[1/5] Cloning ArduPilot repository to $target_dir..."
        git clone https://github.com/ArduPilot/ardupilot.git "$target_dir"
    else
        echo "[1/5] Found ArduPilot directory at $target_dir."
    fi
    
    cd "$target_dir" || return 1
    
    echo "[2/5] Updating git submodules..."
    git submodule update --init --recursive
    
    echo "[3/5] Installing ArduPilot prerequisites..."
    if [ -f "Tools/environment_install/install-prereqs-ubuntu.sh" ]; then
        bash Tools/environment_install/install-prereqs-ubuntu.sh -y
        [ -f "$HOME/.profile" ] && source "$HOME/.profile"
    fi
    
    echo "[4/5] Configuring waf for SITL build..."
    ./waf configure --board sitl
    
    echo "[5/5] Building SITL vehicle binaries (plane & copter)..."
    ./waf plane && ./waf copter
    
    echo "================================"
    echo "[SUCCESS] Automatic SITL Setup Completed!"
    echo "================================"
    ARDUPILOT_DIR="$target_dir"
}

# Function to launch ArduPilot SITL in a new terminal window
launch_sitl() {
    local target_dir="${ARDUPILOT_DIR:-$(find_target_dir "ardupilot")}"
    
    if [ -z "$target_dir" ] || [ ! -d "$target_dir" ]; then
        echo "[ERROR] ArduPilot directory not found on disk."
        read -p "Would you like to automatically setup & fix SITL now? [y/N]: " FIX_ANS
        if [[ "$FIX_ANS" =~ ^[Yy]$ ]]; then
            auto_fix_sitl
            target_dir="$ARDUPILOT_DIR"
        else
            return 1
        fi
    fi
    
    local vehicle="ArduPlane"
    local frame="gazebo-zephyr"
    local param_file=""

    # Check SITL_Models configs first for matching parameter file
    if [ -n "$SITL_MODELS_DIR" ] && [ -d "$SITL_MODELS_DIR/Gazebo/config" ]; then
        for pfile in "$SITL_MODELS_DIR/Gazebo/config"/*.param; do
            [ -f "$pfile" ] || continue
            local pbase=$(basename "$pfile" .param)
            if [[ "$SELECTED_WORLD" =~ "$pbase" ]]; then
                param_file="$pfile"
                break
            fi
        done
    fi

    # Determine vehicle type and frame based on selected world name
    if [[ "$SELECTED_WORLD" =~ (rover|r1_rover|sawppy|lawnmower|catamaran|blueboat|omni|wildthumper|truck|daf) ]]; then
        vehicle="ArduRover"
        frame="gazebo-rover"
    elif [[ "$SELECTED_WORLD" =~ (iris|hexapod|bicopter|quadruped) ]]; then
        vehicle="ArduCopter"
        frame="gazebo-iris"
    elif [[ "$SELECTED_WORLD" =~ (zephyr|skywalker|vtail|swan|alti|skycat|wsc) ]]; then
        vehicle="ArduPlane"
        frame="gazebo-zephyr"
    fi

    # Fallback to ardupilot_gazebo parameter files if not matched in SITL_Models
    if [ -z "$param_file" ]; then
        if [[ "$SELECTED_WORLD" =~ iris ]]; then
            param_file="$GAZEBO_DIR/config/gazebo-iris-gimbal.parm"
        elif [[ "$SELECTED_WORLD" =~ zephyr ]]; then
            param_file="$GAZEBO_DIR/config/gazebo-zephyr-gimbal.parm"
        fi
    fi
    
    local param_arg=""
    if [ -n "$param_file" ] && [ -f "$param_file" ]; then
        param_arg="--add-param-file=$param_file"
    fi
    
    local sitl_cmd="cd \"$target_dir\" && python3 Tools/autotest/sim_vehicle.py -v $vehicle -f $frame --model JSON $param_arg --console --map"
    
    echo "================================"
    echo "Launching SITL in a new terminal window..."
    echo "Vehicle: $vehicle | Frame: $frame"
    [ -n "$param_file" ] && echo "Param File: $param_file"
    echo "Command: $sitl_cmd"
    echo "================================"
    
    launch_in_new_terminal "$sitl_cmd" "ArduPilot SITL - $vehicle"
}

# Initialize WSL GUI environment if running on WSL
setup_wsl_gui_env

echo "================================"
echo "Scanning for ardupilot_gazebo & SITL_Models..."
echo "================================"

# Step 1: Scan disk for ardupilot_gazebo and SITL_Models
GAZEBO_DIR=$(find_target_dir "ardupilot_gazebo")
SITL_MODELS_DIR=$(find_target_dir "SITL_Models")

if [ -n "$GAZEBO_DIR" ]; then
    echo "FOUND ardupilot_gazebo directory at: $GAZEBO_DIR"
    
    # Check if required subdirectories exist
    [ -d "$GAZEBO_DIR/build" ] && echo "  - build directory:  FOUND ($GAZEBO_DIR/build)" || echo "  - build directory:  NOT FOUND ($GAZEBO_DIR/build)"
    [ -d "$GAZEBO_DIR/models" ] && echo "  - models directory: FOUND ($GAZEBO_DIR/models)" || echo "  - models directory: NOT FOUND ($GAZEBO_DIR/models)"
    [ -d "$GAZEBO_DIR/worlds" ] && echo "  - worlds directory: FOUND ($GAZEBO_DIR/worlds)" || echo "  - worlds directory: NOT FOUND ($GAZEBO_DIR/worlds)"
else
    echo "NOT FOUND: ardupilot_gazebo directory in $HOME, $HOME/JSetup, or child directories."
    read -p "Would you like to run setup_gazebo.sh to install & configure Gazebo automatically? [y/N]: " SETUP_NOW
    if [[ "$SETUP_NOW" =~ ^[Yy]$ ]]; then
        run_setup_gazebo
    fi
fi

echo ""
if [ -n "$SITL_MODELS_DIR" ]; then
    echo "FOUND official ArduPilot SITL_Models directory at: $SITL_MODELS_DIR"
    [ -d "$SITL_MODELS_DIR/Gazebo/models" ] && echo "  - models directory: FOUND ($SITL_MODELS_DIR/Gazebo/models)" || echo "  - models directory: NOT FOUND ($SITL_MODELS_DIR/Gazebo/models)"
    [ -d "$SITL_MODELS_DIR/Gazebo/worlds" ] && echo "  - worlds directory: FOUND ($SITL_MODELS_DIR/Gazebo/worlds)" || echo "  - worlds directory: NOT FOUND ($SITL_MODELS_DIR/Gazebo/worlds)"
else
    echo "NOT FOUND: official ArduPilot SITL_Models directory in $HOME, $HOME/JSetup, or child directories."
    read -p "Would you like to download official ArduPilot SITL_Models repository now? [y/N]: " DL_SITL_NOW
    if [[ "$DL_SITL_NOW" =~ ^[Yy]$ ]]; then
        download_sitl_models
    fi
fi

echo ""
echo "================================"
echo "Checking ~/.bashrc configuration for Gazebo..."
echo "================================"

PLUGIN_VAR=$(grep -E '^[[:space:]]*(export[[:space:]]+)?GZ_SIM_SYSTEM_PLUGIN_PATH=' "$BASHRC" 2>/dev/null | tail -n 1)
RESOURCE_VAR=$(grep -E '^[[:space:]]*(export[[:space:]]+)?GZ_SIM_RESOURCE_PATH=' "$BASHRC" 2>/dev/null | tail -n 1)

PLUGIN_PATH=""
RESOURCE_PATH=""

if [ -n "$PLUGIN_VAR" ]; then
    PLUGIN_PATH=$(echo "$PLUGIN_VAR" | sed -E 's/^[[:space:]]*(export[[:space:]]+)?GZ_SIM_SYSTEM_PLUGIN_PATH=//')
    PLUGIN_PATH=$(echo "$PLUGIN_PATH" | sed -E 's/^["'\''[:space:]]+|["'\''[:space:]]+$//g')
    echo "GZ_SIM_SYSTEM_PLUGIN_PATH in ~/.bashrc:"
    echo "  $PLUGIN_PATH"
else
    echo "GZ_SIM_SYSTEM_PLUGIN_PATH NOT FOUND in ~/.bashrc"
fi

echo ""

if [ -n "$RESOURCE_VAR" ]; then
    RESOURCE_PATH=$(echo "$RESOURCE_VAR" | sed -E 's/^[[:space:]]*(export[[:space:]]+)?GZ_SIM_RESOURCE_PATH=//')
    RESOURCE_PATH=$(echo "$RESOURCE_PATH" | sed -E 's/^["'\''[:space:]]+|["'\''[:space:]]+$//g')
    echo "GZ_SIM_RESOURCE_PATH in ~/.bashrc:"
    echo "  $RESOURCE_PATH"
else
    echo "GZ_SIM_RESOURCE_PATH NOT FOUND in ~/.bashrc"
fi

echo ""
echo "Validating plugin paths on disk..."

PLUGIN_OK=false

if [ -n "$PLUGIN_PATH" ]; then
    IFS=':' read -ra PLUGIN_DIRS <<< "$PLUGIN_PATH"

    for RAW_DIR in "${PLUGIN_DIRS[@]}"; do
        if [[ "$RAW_DIR" == '$GZ_SIM_SYSTEM_PLUGIN_PATH' || "$RAW_DIR" == '${GZ_SIM_SYSTEM_PLUGIN_PATH}' ]]; then
            continue
        fi

        DIR=$(expand_path "$RAW_DIR")
        if [ -z "$DIR" ]; then
            continue
        fi

        if [ -d "$DIR" ]; then
            echo "  [OK] FOUND: $DIR"
            PLUGIN_OK=true
        else
            echo "  [FAIL] NOT FOUND: $DIR"
        fi
    done
else
    echo "  [FAIL] No plugin path configured."
fi

echo ""
echo "Validating resource paths on disk..."

RESOURCE_OK=false

if [ -n "$RESOURCE_PATH" ]; then
    IFS=':' read -ra RESOURCE_DIRS <<< "$RESOURCE_PATH"

    for RAW_DIR in "${RESOURCE_DIRS[@]}"; do
        if [[ "$RAW_DIR" == '$GZ_SIM_RESOURCE_PATH' || "$RAW_DIR" == '${GZ_SIM_RESOURCE_PATH}' ]]; then
            continue
        fi

        DIR=$(expand_path "$RAW_DIR")
        if [ -z "$DIR" ]; then
            continue
        fi

        if [ -d "$DIR" ]; then
            echo "  [OK] FOUND: $DIR"
            RESOURCE_OK=true
        else
            echo "  [FAIL] NOT FOUND: $DIR"
        fi
    done
else
    echo "  [FAIL] No resource path configured."
fi

echo ""
echo "================================"
echo "Gazebo environment summary"
echo "================================"

if [ "$PLUGIN_OK" = true ] && [ "$RESOURCE_OK" = true ]; then
    echo "STATUS: Gazebo environment configuration in ~/.bashrc is VALID."
else
    echo "STATUS: Gazebo environment configuration in ~/.bashrc is INVALID or INCORRECT."
    echo ""
    auto_fix_gazebo
fi

echo ""
echo "================================"
echo "Scanning for ArduPilot installation..."
echo "================================"

ARDUPILOT_DIR=$(find_target_dir "ardupilot")

if [ -n "$ARDUPILOT_DIR" ]; then
    echo "FOUND ArduPilot directory at: $ARDUPILOT_DIR"
    if [ -f "$ARDUPILOT_DIR/Tools/autotest/sim_vehicle.py" ] || [ -f "$ARDUPILOT_DIR/waf" ]; then
        echo "STATUS: ArduPilot installation is VALID."
    else
        echo "STATUS: WARNING - ArduPilot directory found at $ARDUPILOT_DIR, but build/sim scripts (waf / sim_vehicle.py) were not found."
    fi
else
    echo "STATUS: NOT FOUND - ardupilot directory not found in $HOME, $HOME/JSetup, or 1 child directory under $HOME."
    echo "To install ArduPilot, run:"
    echo "  git clone https://github.com/ArduPilot/ardupilot.git ~/ardupilot"
fi

# Function for Fix Menu options
show_fix_menu() {
    while true; do
        echo ""
        echo "================================"
        echo "Fix & Setup Options:"
        echo "================================"
        echo "  1) Download / Update official models from official repos (SITL_Models)"
        echo "  2) Automatically Fix / Setup SITL (Install prerequisites & build SITL)"
        echo "  3) Automatically Fix Gazebo environment paths in ~/.bashrc"
        echo "  0) Back to Previous Menu"
        echo "================================"
        read -p "Select fix option [0-3]: " FIX_CHOICE
        
        case "$FIX_CHOICE" in
            1)
                download_sitl_models
                ;;
            2)
                auto_fix_sitl
                ;;
            3)
                auto_fix_gazebo
                ;;
            0)
                break
                ;;
            *)
                echo "Invalid option. Please enter 0, 1, 2, or 3."
                ;;
        esac
    done
}

# Function for Post-Launch Menu options when Gazebo is running
post_launch_menu() {
    while true; do
        echo ""
        echo "================================"
        echo "Gazebo simulation running in separate terminal."
        if [ -n "$SELECTED_DISPLAY" ]; then
            echo "Current Model/World: $SELECTED_DISPLAY"
        fi
        echo "What would you like to do next?"
        echo "================================"
        echo "  1) Launch SITL (ArduPilot simulation vehicle) in a new terminal"
        echo "  2) Continue to launch (Select & launch another Gazebo model)"
        echo "  3) Fix menu (Download models, Fix SITL, Fix Gazebo paths)"
        echo "  0) Exit"
        echo "================================"
        read -p "Select action [0-3]: " NEXT_ACTION
        
        case "$NEXT_ACTION" in
            1)
                launch_sitl
                ;;
            2)
                select_and_launch_gazebo
                break
                ;;
            3)
                show_fix_menu
                ;;
            0)
                echo "Exiting script."
                exit 0
                ;;
            *)
                echo "Invalid option. Please enter 0, 1, 2, or 3."
                ;;
        esac
    done
}

# Function to select and launch a Gazebo model
select_and_launch_gazebo() {
    if [ "$PLUGIN_OK" != true ] || [ "$RESOURCE_OK" != true ] || [ -z "$GAZEBO_DIR" ]; then
        echo "[WARNING] Gazebo setup or paths are not properly configured."
        auto_fix_gazebo
    fi

    WORLDS_DISPLAY=()
    WORLD_FILES=()

    if [ -n "$GAZEBO_DIR" ] && [ -d "$GAZEBO_DIR/worlds" ]; then
        for w in "$GAZEBO_DIR/worlds"/*.sdf; do
            [ -f "$w" ] || continue
            WORLDS_DISPLAY+=("[ardupilot_gazebo] $(basename "$w")")
            WORLD_FILES+=("$(basename "$w")")
        done
    fi

    if [ -n "$SITL_MODELS_DIR" ] && [ -d "$SITL_MODELS_DIR/Gazebo/worlds" ]; then
        for w in "$SITL_MODELS_DIR/Gazebo/worlds"/*.sdf; do
            [ -f "$w" ] || continue
            WORLDS_DISPLAY+=("[SITL_Models] $(basename "$w")")
            WORLD_FILES+=("$(basename "$w")")
        done
    fi

    if [ ${#WORLDS_DISPLAY[@]} -eq 0 ]; then
        echo "[WARNING] No world (.sdf) files found in Gazebo resource directories."
        return 1
    fi

    local show_all=false

    while true; do
        echo ""
        echo "================================"
        echo "Available Gazebo Simulation Models / Worlds:"
        echo "================================"

        local total_models=${#WORLDS_DISPLAY[@]}
        local limit=$total_models

        if [ "$show_all" = false ] && [ $total_models -gt 6 ]; then
            limit=6
        fi

        for (( i=0; i<limit; i++ )); do
            num=$((i+1))
            echo "  $num) ${WORLDS_DISPLAY[$i]}"
        done

        if [ "$show_all" = false ] && [ $total_models -gt 6 ]; then
            echo "  7) Show more models ($((total_models - 6)) more available)"
            echo "  0) Back to Main Menu"
            echo "================================"
            read -p "Enter option number [1-6 to launch, 7 for more, 0 to back]: " CHOICE
        else
            echo "  0) Back to Main Menu"
            echo "================================"
            read -p "Enter option number to launch Gazebo [1-$total_models, 0]: " CHOICE
        fi

        if [ "$show_all" = false ] && [ $total_models -gt 6 ] && [ "$CHOICE" = "7" ]; then
            show_all=true
            continue
        fi

        if [ "$CHOICE" = "0" ]; then
            echo "Returning to main menu."
            return 0
        fi

        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "$limit" ]; then
            INDEX=$((CHOICE-1))
            SELECTED_WORLD="${WORLD_FILES[$INDEX]}"
            SELECTED_DISPLAY="${WORLDS_DISPLAY[$INDEX]}"
            echo ""
            echo "================================"
            echo "Launching Gazebo in a new terminal window..."
            echo "Model/World: $SELECTED_DISPLAY"
            echo "Command: gz sim -v4 -r \"$SELECTED_WORLD\""
            echo "================================"
            
            LAUNCH_RESOURCE_PATH="$GAZEBO_DIR/models:$GAZEBO_DIR/worlds"
            if [ -n "$SITL_MODELS_DIR" ] && [ -d "$SITL_MODELS_DIR/Gazebo" ]; then
                LAUNCH_RESOURCE_PATH="$LAUNCH_RESOURCE_PATH:$SITL_MODELS_DIR/Gazebo/models:$SITL_MODELS_DIR/Gazebo/worlds"
            fi

            LAUNCH_CMD="export GZ_SIM_SYSTEM_PLUGIN_PATH=\"$GAZEBO_DIR/build:\$GZ_SIM_SYSTEM_PLUGIN_PATH\"; export GZ_SIM_RESOURCE_PATH=\"$LAUNCH_RESOURCE_PATH:\$GZ_SIM_RESOURCE_PATH\"; gz sim -v4 -r \"$SELECTED_WORLD\""
            
            launch_in_new_terminal "$LAUNCH_CMD" "Gazebo Sim - $SELECTED_WORLD"
            
            # Open post-launch menu
            post_launch_menu
            return 0
        else
            echo "Invalid selection. Please try again."
        fi
    done
}

# Function for main menu after scan
main_menu() {
    while true; do
        echo ""
        echo "================================"
        echo "Scan completed. Everything seems OK!"
        echo "What would you like to do?"
        echo "================================"
        echo "  1) Launch Gazebo"
        echo "  2) Download / Update official models from official repos (SITL_Models)"
        echo "  3) Fix / Setup SITL (Install prerequisites & build SITL)"
        echo "  4) Fix Gazebo paths in ~/.bashrc"
        echo "  0) Exit"
        echo "================================"
        read -p "Select option [0-4]: " MAIN_CHOICE

        case "$MAIN_CHOICE" in
            1)
                select_and_launch_gazebo
                ;;
            2)
                download_sitl_models
                ;;
            3)
                auto_fix_sitl
                ;;
            4)
                auto_fix_gazebo
                ;;
            0)
                echo "Exiting script."
                exit 0
                ;;
            *)
                echo "Invalid option. Please enter 0, 1, 2, 3, or 4."
                ;;
        esac
    done
}

main_menu

exec bash