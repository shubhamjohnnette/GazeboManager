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

# Helper function to launch a command in a new terminal window
launch_in_new_terminal() {
    local cmd="$1"
    local title="${2:-Gazebo Simulation}"
    
    if command -v gnome-terminal &>/dev/null; then
        gnome-terminal --title="$title" -- bash -c "$cmd; exec bash" &
    elif command -v xfce4-terminal &>/dev/null; then
        xfce4-terminal --title="$title" -e "bash -c \"$cmd; exec bash\"" &
    elif command -v konsole &>/dev/null; then
        konsole --title="$title" -e bash -c "$cmd; exec bash" &
    elif command -v xterm &>/dev/null; then
        xterm -T "$title" -e "bash -c \"$cmd; exec bash\"" &
    else
        echo "[WARNING] Terminal emulator not detected. Launching in current terminal..."
        eval "$cmd"
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

# Function to automatically fix Gazebo environment variables in ~/.bashrc
auto_fix_gazebo() {
    if [ -n "$GAZEBO_DIR" ]; then
        echo "[AUTO-FIX] Updating ~/.bashrc with correct Gazebo paths..."
        sed -i '/GZ_SIM_SYSTEM_PLUGIN_PATH/d' "$BASHRC" 2>/dev/null
        sed -i '/GZ_SIM_RESOURCE_PATH/d' "$BASHRC" 2>/dev/null
        echo "export GZ_SIM_SYSTEM_PLUGIN_PATH=$GAZEBO_DIR/build:\$GZ_SIM_SYSTEM_PLUGIN_PATH" >> "$BASHRC"
        echo "export GZ_SIM_RESOURCE_PATH=$GAZEBO_DIR/models:$GAZEBO_DIR/worlds:\$GZ_SIM_RESOURCE_PATH" >> "$BASHRC"
        export GZ_SIM_SYSTEM_PLUGIN_PATH="$GAZEBO_DIR/build:$GZ_SIM_SYSTEM_PLUGIN_PATH"
        export GZ_SIM_RESOURCE_PATH="$GAZEBO_DIR/models:$GAZEBO_DIR/worlds:$GZ_SIM_RESOURCE_PATH"
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
    local param_file="$GAZEBO_DIR/config/gazebo-zephyr-gimbal.parm"
    
    if [[ "$SELECTED_WORLD" =~ iris ]]; then
        vehicle="ArduCopter"
        frame="gazebo-iris"
        param_file="$GAZEBO_DIR/config/gazebo-iris-gimbal.parm"
    fi
    
    local param_arg=""
    if [ -f "$param_file" ]; then
        param_arg="--add-param-file=$param_file"
    fi
    
    local sitl_cmd="cd \"$target_dir\" && python3 Tools/autotest/sim_vehicle.py -v $vehicle -f $frame --model JSON $param_arg --console --map"
    
    echo "================================"
    echo "Launching SITL in a new terminal window..."
    echo "Vehicle: $vehicle | Frame: $frame"
    echo "Command: $sitl_cmd"
    echo "================================"
    
    launch_in_new_terminal "$sitl_cmd" "ArduPilot SITL - $vehicle"
}

echo "================================"
echo "Scanning for ardupilot_gazebo..."
echo "================================"

# Step 1: Scan disk for ardupilot_gazebo first
GAZEBO_DIR=$(find_target_dir "ardupilot_gazebo")

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

echo ""
echo "================================"
echo "Scan completed."
echo "================================"

# If Gazebo configuration is valid, prompt user to select and launch a model/world
if [ "$PLUGIN_OK" = true ] && [ "$RESOURCE_OK" = true ] && [ -n "$GAZEBO_DIR" ]; then
    WORLDS=()
    if [ -d "$GAZEBO_DIR/worlds" ]; then
        for w in "$GAZEBO_DIR/worlds"/*.sdf; do
            [ -f "$w" ] || continue
            WORLDS+=("$(basename "$w")")
        done
    fi

    if [ ${#WORLDS[@]} -gt 0 ]; then
        echo ""
        echo "================================"
        echo "Available Gazebo Simulation Models / Worlds:"
        echo "================================"
        for i in "${!WORLDS[@]}"; do
            num=$((i+1))
            echo "  $num) ${WORLDS[$i]}"
        done
        echo "  0) Exit without launching"
        echo "================================"
        
        read -p "Enter option number to launch Gazebo [1-${#WORLDS[@]}]: " CHOICE
        
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#WORLDS[@]}" ]; then
            INDEX=$((CHOICE-1))
            SELECTED_WORLD="${WORLDS[$INDEX]}"
            echo ""
            echo "================================"
            echo "Launching Gazebo in a new terminal window..."
            echo "Model/World: $SELECTED_WORLD"
            echo "Command: gz sim -v4 -r \"$SELECTED_WORLD\""
            echo "================================"
            
            LAUNCH_CMD="export GZ_SIM_SYSTEM_PLUGIN_PATH=\"$GAZEBO_DIR/build:\$GZ_SIM_SYSTEM_PLUGIN_PATH\"; export GZ_SIM_RESOURCE_PATH=\"$GAZEBO_DIR/models:$GAZEBO_DIR/worlds:\$GZ_SIM_RESOURCE_PATH\"; gz sim -v4 -r \"$SELECTED_WORLD\""
            
            launch_in_new_terminal "$LAUNCH_CMD" "Gazebo Sim - $SELECTED_WORLD"
            
            # Post-launch interactive options menu
            while true; do
                echo ""
                echo "================================"
                echo "Gazebo simulation running in separate terminal."
                echo "What would you like to do next?"
                echo "================================"
                echo "  1) Launch SITL (ArduPilot simulation vehicle) in a new terminal"
                echo "  2) Automatically Fix / Setup SITL (Install prerequisites & build SITL)"
                echo "  3) Automatically Fix Gazebo paths in ~/.bashrc"
                echo "  0) Exit"
                echo "================================"
                read -p "Select action [0-3]: " NEXT_ACTION
                
                case "$NEXT_ACTION" in
                    1)
                        launch_sitl
                        ;;
                    2)
                        auto_fix_sitl
                        ;;
                    3)
                        auto_fix_gazebo
                        ;;
                    0)
                        echo "Exiting script."
                        break
                        ;;
                    *)
                        echo "Invalid option. Please enter 0, 1, 2, or 3."
                        ;;
                esac
            done
            
        elif [ "$CHOICE" = "0" ]; then
            echo "Exiting script without launching Gazebo."
        else
            echo "Invalid selection or no input provided. Skipping Gazebo launch."
        fi
    else
        echo "No world (.sdf) files found in $GAZEBO_DIR/worlds."
    fi
fi

exec bash