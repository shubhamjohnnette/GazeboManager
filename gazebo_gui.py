#!/usr/bin/env python3
"""
GazeboManager GUI Application
=============================
A modern Python Tkinter GUI to configure remote SSH or WSL connections,
copy check.sh and setup_gazebo.sh to target systems, and execute Gazebo/SITL
operations by launching target terminal windows.
"""

import os
import sys
import shutil
import subprocess
import threading
import queue
import time
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext

# ---------------------------------------------------------
# CONSTANTS & THEME
# ---------------------------------------------------------
COLOR_BG_MAIN = "#1e1e2e"       # Base Dark
COLOR_BG_CARD = "#282a36"       # Card / Section Frame
COLOR_BG_INPUT = "#181825"      # Input fields
COLOR_TEXT_MAIN = "#f8f8f2"     # Primary Text
COLOR_TEXT_MUTED = "#a6adc8"    # Subtitle / Muted Text

COLOR_PRIMARY = "#805ad5"       # Violet Accent
COLOR_PRIMARY_HOVER = "#6b46c1"
COLOR_SUCCESS = "#10b981"       # Emerald Green Accent
COLOR_SUCCESS_HOVER = "#059669"
COLOR_INFO = "#3b82f6"          # Blue Accent
COLOR_WARNING = "#f59e0b"       # Amber Accent
COLOR_DANGER = "#ef4444"        # Coral Red Accent

FONT_TITLE = ("Segoe UI", 16, "bold")
FONT_HEADER = ("Segoe UI", 12, "bold")
FONT_LABEL = ("Segoe UI", 10, "bold")
FONT_BODY = ("Segoe UI", 10)
FONT_CONSOLE = ("Consolas", 9)


class GazeboManagerGUI(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("GazeboManager - Remote SITL & Simulation Hub")
        self.geometry("980x820")
        self.minsize(850, 700)
        self.configure(bg=COLOR_BG_MAIN)

        self.script_dir = os.path.dirname(os.path.abspath(__file__))
        self.log_queue = queue.Queue()

        # Target Variables
        self.target_mode_var = tk.StringVar(value="SSH")  # "SSH" or "WSL"
        self.host_var = tk.StringVar(value="192.168.1.100")
        self.wsl_distro_var = tk.StringVar(value="Ubuntu")
        self.port_var = tk.StringVar(value="22")
        self.username_var = tk.StringVar(value=os.environ.get("USER", "ubuntu"))
        self.password_var = tk.StringVar(value="")
        self.target_path_var = tk.StringVar(value="~/GazeboManager")
        self.show_password_var = tk.BooleanVar(value=False)
        self.selected_world_var = tk.StringVar(value="zephyr_gimbal_runway.sdf")

        # Terminal detection
        self.terminal_emulator = self._detect_terminal_emulator()

        # Build UI
        self._init_styles()
        self._create_layout()

        # Start periodic log queue consumer
        self.after(100, self._process_log_queue)
        
        # Check dependencies on startup
        self.after(500, self._check_system_dependencies)

    # ---------------------------------------------------------
    # UI SETUP & STYLING
    # ---------------------------------------------------------
    def _init_styles(self):
        self.style = ttk.Style(self)
        self.style.theme_use("clam")

        # General TTK Styles
        self.style.configure(".", background=COLOR_BG_MAIN, foreground=COLOR_TEXT_MAIN, font=FONT_BODY)
        self.style.configure("TFrame", background=COLOR_BG_MAIN)
        self.style.configure("Card.TFrame", background=COLOR_BG_CARD, relief="flat")
        
        self.style.configure("TLabel", background=COLOR_BG_CARD, foreground=COLOR_TEXT_MAIN, font=FONT_BODY)
        self.style.configure("Header.TLabel", font=FONT_HEADER, foreground=COLOR_TEXT_MAIN)
        self.style.configure("Title.TLabel", font=FONT_TITLE, foreground=COLOR_PRIMARY)
        self.style.configure("Muted.TLabel", font=FONT_BODY, foreground=COLOR_TEXT_MUTED)

        self.style.configure("TRadiobutton", background=COLOR_BG_CARD, foreground=COLOR_TEXT_MAIN, font=FONT_LABEL)
        self.style.map("TRadiobutton", background=[("active", COLOR_BG_CARD)])

        self.style.configure("TCombobox", fieldbackground=COLOR_BG_INPUT, background=COLOR_BG_CARD, foreground=COLOR_TEXT_MAIN)

    def _create_layout(self):
        # Main scrollable canvas container or structured layout
        main_container = ttk.Frame(self, style="TFrame")
        main_container.pack(fill=tk.BOTH, expand=True, padx=15, pady=15)

        # Header Title Banner
        self._create_header(main_container)

        # Connection Configuration Card
        self._create_connection_card(main_container)

        # Operations Dashboard Card
        self._create_dashboard_card(main_container)

        # Console Log & Status Bar
        self._create_console_card(main_container)

    def _create_header(self, parent):
        header_frame = ttk.Frame(parent, style="TFrame")
        header_frame.pack(fill=tk.X, pady=(0, 10))

        title_lbl = ttk.Label(header_frame, text="🛸 GazeboManager Controller", style="Title.TLabel")
        title_lbl.pack(side=tk.LEFT)

        subtitle_lbl = ttk.Label(
            header_frame,
            text="Deploy & Control Gazebo + ArduPilot SITL Simulations Remotely",
            style="Muted.TLabel"
        )
        subtitle_lbl.pack(side=tk.RIGHT, pady=(5, 0))

    def _create_connection_card(self, parent):
        card = ttk.Frame(parent, style="Card.TFrame", padding=15)
        card.pack(fill=tk.X, pady=(0, 10))

        # Title & Mode Switch
        top_row = ttk.Frame(card, style="Card.TFrame")
        top_row.pack(fill=tk.X, pady=(0, 10))

        card_title = ttk.Label(top_row, text="1. Target Connection Setup", style="Header.TLabel")
        card_title.pack(side=tk.LEFT)

        mode_frame = ttk.Frame(top_row, style="Card.TFrame")
        mode_frame.pack(side=tk.RIGHT)

        rb_ssh = ttk.Radiobutton(
            mode_frame, text="🌐 Remote SSH (IP)", value="SSH",
            variable=self.target_mode_var, command=self._toggle_target_mode, style="TRadiobutton"
        )
        rb_ssh.pack(side=tk.LEFT, padx=(0, 15))

        rb_wsl = ttk.Radiobutton(
            mode_frame, text="🐧 WSL (Local/Remote)", value="WSL",
            variable=self.target_mode_var, command=self._toggle_target_mode, style="TRadiobutton"
        )
        rb_wsl.pack(side=tk.LEFT)

        # Form Inputs Grid
        grid_frame = ttk.Frame(card, style="Card.TFrame")
        grid_frame.pack(fill=tk.X)

        # Row 0: Host / Distro & Port
        self.lbl_host = ttk.Label(grid_frame, text="Host IP Address:", style="TLabel")
        self.lbl_host.grid(row=0, column=0, sticky="w", padx=5, pady=5)

        self.entry_host = tk.Entry(
            grid_frame, textvariable=self.host_var, bg=COLOR_BG_INPUT, fg=COLOR_TEXT_MAIN,
            insertbackground=COLOR_TEXT_MAIN, font=FONT_BODY, relief="solid", bd=1
        )
        self.entry_host.grid(row=0, column=1, sticky="ew", padx=5, pady=5)

        self.lbl_port = ttk.Label(grid_frame, text="Port:", style="TLabel")
        self.lbl_port.grid(row=0, column=2, sticky="w", padx=(15, 5), pady=5)

        self.entry_port = tk.Entry(
            grid_frame, textvariable=self.port_var, width=8, bg=COLOR_BG_INPUT, fg=COLOR_TEXT_MAIN,
            insertbackground=COLOR_TEXT_MAIN, font=FONT_BODY, relief="solid", bd=1
        )
        self.entry_port.grid(row=0, column=3, sticky="w", padx=5, pady=5)

        # Row 1: Username & Password
        lbl_user = ttk.Label(grid_frame, text="Username:", style="TLabel")
        lbl_user.grid(row=1, column=0, sticky="w", padx=5, pady=5)

        entry_user = tk.Entry(
            grid_frame, textvariable=self.username_var, bg=COLOR_BG_INPUT, fg=COLOR_TEXT_MAIN,
            insertbackground=COLOR_TEXT_MAIN, font=FONT_BODY, relief="solid", bd=1
        )
        entry_user.grid(row=1, column=1, sticky="ew", padx=5, pady=5)

        lbl_pass = ttk.Label(grid_frame, text="Password:", style="TLabel")
        lbl_pass.grid(row=1, column=2, sticky="w", padx=(15, 5), pady=5)

        pass_frame = ttk.Frame(grid_frame, style="Card.TFrame")
        pass_frame.grid(row=1, column=3, columnspan=2, sticky="ew", padx=5, pady=5)

        self.entry_pass = tk.Entry(
            pass_frame, textvariable=self.password_var, show="*", bg=COLOR_BG_INPUT, fg=COLOR_TEXT_MAIN,
            insertbackground=COLOR_TEXT_MAIN, font=FONT_BODY, relief="solid", bd=1
        )
        self.entry_pass.pack(side=tk.LEFT, fill=tk.X, expand=True)

        btn_show_pass = tk.Button(
            pass_frame, text="👁", command=self._toggle_show_password, bg=COLOR_BG_CARD,
            fg=COLOR_TEXT_MAIN, activebackground=COLOR_BG_MAIN, activeforeground=COLOR_TEXT_MAIN,
            bd=0, cursor="hand2", font=("Segoe UI", 9)
        )
        btn_show_pass.pack(side=tk.RIGHT, padx=(4, 0))

        # Row 2: Target Path
        lbl_path = ttk.Label(grid_frame, text="Target Path:", style="TLabel")
        lbl_path.grid(row=2, column=0, sticky="w", padx=5, pady=5)

        entry_path = tk.Entry(
            grid_frame, textvariable=self.target_path_var, bg=COLOR_BG_INPUT, fg=COLOR_TEXT_MAIN,
            insertbackground=COLOR_TEXT_MAIN, font=FONT_BODY, relief="solid", bd=1
        )
        entry_path.grid(row=2, column=1, columnspan=3, sticky="ew", padx=5, pady=5)

        grid_frame.columnconfigure(1, weight=1)
        grid_frame.columnconfigure(3, weight=1)

        # Action Buttons Row (Test Connection & Copy Files)
        btn_row = ttk.Frame(card, style="Card.TFrame")
        btn_row.pack(fill=tk.X, pady=(10, 0))

        self.btn_test = tk.Button(
            btn_row, text="🔌 Test Connection", command=self.test_connection,
            bg=COLOR_INFO, fg="white", activebackground="#2563eb", activeforeground="white",
            font=FONT_LABEL, bd=0, padx=15, pady=6, cursor="hand2"
        )
        self.btn_test.pack(side=tk.LEFT, padx=(0, 10))

        self.btn_copy = tk.Button(
            btn_row, text="📦 Copy Files to Target System", command=self.copy_files_to_target,
            bg=COLOR_PRIMARY, fg="white", activebackground=COLOR_PRIMARY_HOVER, activeforeground="white",
            font=FONT_LABEL, bd=0, padx=15, pady=6, cursor="hand2"
        )
        self.btn_copy.pack(side=tk.LEFT)

    def _create_dashboard_card(self, parent):
        card = ttk.Frame(parent, style="Card.TFrame", padding=15)
        card.pack(fill=tk.X, pady=(0, 10))

        card_title = ttk.Label(card, text="2. Target Operations Dashboard", style="Header.TLabel")
        card_title.pack(anchor="w", pady=(0, 10))

        # Dashboard Grid layout with categories
        grid = ttk.Frame(card, style="Card.TFrame")
        grid.pack(fill=tk.X)

        # Column 1: Core & Setup Scripts
        col1 = ttk.Frame(grid, style="Card.TFrame")
        col1.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=5)

        lbl_sec1 = ttk.Label(col1, text="🚀 Core Automation", font=FONT_LABEL, foreground=COLOR_INFO)
        lbl_sec1.pack(anchor="w", pady=(0, 5))

        btn_run_check = tk.Button(
            col1, text="▶ Run Manager (check.sh)",
            command=lambda: self.launch_remote_command("bash ~/GazeboManager/check.sh", "Gazebo & SITL Manager"),
            bg="#312e81", fg=COLOR_TEXT_MAIN, activebackground="#4338ca", activeforeground="white",
            font=FONT_BODY, bd=0, pady=8, anchor="w", padx=10, cursor="hand2"
        )
        btn_run_check.pack(fill=tk.X, pady=3)

        btn_run_setup = tk.Button(
            col1, text="⚙ Setup Gazebo (setup_gazebo.sh)",
            command=lambda: self.launch_remote_command("bash ~/GazeboManager/setup_gazebo.sh", "Gazebo Setup"),
            bg="#312e81", fg=COLOR_TEXT_MAIN, activebackground="#4338ca", activeforeground="white",
            font=FONT_BODY, bd=0, pady=8, anchor="w", padx=10, cursor="hand2"
        )
        btn_run_setup.pack(fill=tk.X, pady=3)

        # Column 2: SITL Vehicle Launchers
        col2 = ttk.Frame(grid, style="Card.TFrame")
        col2.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=5)

        lbl_sec2 = ttk.Label(col2, text="🛩 Vehicle SITL Launch", font=FONT_LABEL, foreground=COLOR_SUCCESS)
        lbl_sec2.pack(anchor="w", pady=(0, 5))

        btn_sitl_plane = tk.Button(
            col2, text="✈ Launch ArduPlane (Zephyr)",
            command=self.launch_sitl_plane,
            bg="#064e3b", fg=COLOR_TEXT_MAIN, activebackground="#047857", activeforeground="white",
            font=FONT_BODY, bd=0, pady=8, anchor="w", padx=10, cursor="hand2"
        )
        btn_sitl_plane.pack(fill=tk.X, pady=3)

        btn_sitl_copter = tk.Button(
            col2, text="🚁 Launch ArduCopter (Iris)",
            command=self.launch_sitl_copter,
            bg="#064e3b", fg=COLOR_TEXT_MAIN, activebackground="#047857", activeforeground="white",
            font=FONT_BODY, bd=0, pady=8, anchor="w", padx=10, cursor="hand2"
        )
        btn_sitl_copter.pack(fill=tk.X, pady=3)

        # Column 3: Gazebo World & Streaming
        col3 = ttk.Frame(grid, style="Card.TFrame")
        col3.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=5)

        lbl_sec3 = ttk.Label(col3, text="🌐 Gazebo & Media", font=FONT_LABEL, foreground=COLOR_WARNING)
        lbl_sec3.pack(anchor="w", pady=(0, 5))

        # World Selector Row
        world_row = ttk.Frame(col3, style="Card.TFrame")
        world_row.pack(fill=tk.X, pady=(0, 3))

        world_cb = ttk.Combobox(
            world_row, textvariable=self.selected_world_var,
            values=["zephyr_gimbal_runway.sdf", "iris_runway.sdf", "default.sdf"],
            state="readonly", font=FONT_BODY
        )
        world_cb.pack(fill=tk.X)

        btn_gz_sim = tk.Button(
            col3, text="🌐 Launch Gazebo World",
            command=self.launch_gazebo_world,
            bg="#78350f", fg=COLOR_TEXT_MAIN, activebackground="#b45309", activeforeground="white",
            font=FONT_BODY, bd=0, pady=6, anchor="w", padx=10, cursor="hand2"
        )
        btn_gz_sim.pack(fill=tk.X, pady=3)

        # Extra Utilities Row
        utils_frame = ttk.Frame(card, style="Card.TFrame")
        utils_frame.pack(fill=tk.X, pady=(10, 0))

        btn_stream = tk.Button(
            utils_frame, text="📡 Enable Video Stream",
            command=self.enable_video_stream,
            bg="#1e293b", fg=COLOR_TEXT_MAIN, activebackground="#334155", activeforeground="white",
            font=FONT_BODY, bd=0, pady=6, padx=12, cursor="hand2"
        )
        btn_stream.pack(side=tk.LEFT, padx=(0, 8))

        btn_receiver = tk.Button(
            utils_frame, text="📺 Receiver (FFplay)",
            command=self.launch_video_receiver,
            bg="#1e293b", fg=COLOR_TEXT_MAIN, activebackground="#334155", activeforeground="white",
            font=FONT_BODY, bd=0, pady=6, padx=12, cursor="hand2"
        )
        btn_receiver.pack(side=tk.LEFT, padx=(0, 8))

        btn_shell = tk.Button(
            utils_frame, text="💻 Open Target Terminal Shell",
            command=lambda: self.launch_remote_command("exec bash", "Target Bash Shell"),
            bg=COLOR_PRIMARY, fg="white", activebackground=COLOR_PRIMARY_HOVER, activeforeground="white",
            font=FONT_LABEL, bd=0, pady=6, padx=12, cursor="hand2"
        )
        btn_shell.pack(side=tk.RIGHT)

    def _create_console_card(self, parent):
        card = ttk.Frame(parent, style="Card.TFrame", padding=10)
        card.pack(fill=tk.BOTH, expand=True)

        lbl_console = ttk.Label(card, text="Console Output & Activity Logs", style="Header.TLabel")
        lbl_console.pack(anchor="w", pady=(0, 5))

        self.txt_console = scrolledtext.ScrolledText(
            card, height=10, bg=COLOR_BG_INPUT, fg=COLOR_TEXT_MAIN,
            insertbackground=COLOR_TEXT_MAIN, font=FONT_CONSOLE, bd=0, relief="flat"
        )
        self.txt_console.pack(fill=tk.BOTH, expand=True)

        # Configure log tags
        self.txt_console.tag_config("INFO", foreground="#38bdf8")
        self.txt_console.tag_config("SUCCESS", foreground="#34d399")
        self.txt_console.tag_config("WARNING", foreground="#fbbf24")
        self.txt_console.tag_config("ERROR", foreground="#f87171")
        self.txt_console.tag_config("CMD", foreground="#c084fc")

        # Status Bar
        self.status_var = tk.StringVar(value="Ready. Terminal emulator detected: " + (self.terminal_emulator or "None"))
        status_bar = ttk.Label(
            card, textvariable=self.status_var, style="Muted.TLabel", anchor="w"
        )
        status_bar.pack(fill=tk.X, pady=(5, 0))

    # ---------------------------------------------------------
    # HELPER & EVENT HANDLERS
    # ---------------------------------------------------------
    def _toggle_target_mode(self):
        mode = self.target_mode_var.get()
        if mode == "SSH":
            self.lbl_host.config(text="Host IP Address:")
            self.entry_host.delete(0, tk.END)
            self.entry_host.insert(0, "192.168.1.100")
            self.lbl_port.grid()
            self.entry_port.grid()
            self.log(f"Switched target mode to Remote SSH (IP)", "INFO")
        else:
            self.lbl_host.config(text="WSL Distro Name:")
            self.entry_host.delete(0, tk.END)
            self.entry_host.insert(0, "Ubuntu")
            self.lbl_port.grid_remove()
            self.entry_port.grid_remove()
            self.log(f"Switched target mode to WSL (Windows Subsystem for Linux)", "INFO")

    def _toggle_show_password(self):
        if self.show_password_var.get():
            self.entry_pass.config(show="*")
            self.show_password_var.set(False)
        else:
            self.entry_pass.config(show="")
            self.show_password_var.set(True)

    def log(self, message, tag="INFO"):
        timestamp = time.strftime("%H:%M:%S")
        formatted = f"[{timestamp}] [{tag}] {message}\n"
        self.log_queue.put((formatted, tag))

    def _process_log_queue(self):
        while not self.log_queue.empty():
            formatted, tag = self.log_queue.get_nowait()
            self.txt_console.insert(tk.END, formatted, tag)
            self.txt_console.see(tk.END)
        self.after(100, self._process_log_queue)

    def set_status(self, text):
        self.status_var.set(text)

    def _detect_terminal_emulator(self):
        terminals = ["gnome-terminal", "xfce4-terminal", "konsole", "xterm", "tilix"]
        for term in terminals:
            if shutil.which(term):
                return term
        return None

    def _check_system_dependencies(self):
        self.log("Initializing GazeboManager GUI system checks...", "INFO")
        if not self.terminal_emulator:
            self.log("WARNING: No supported terminal emulator found (gnome-terminal, xfce4-terminal, konsole, xterm).", "WARNING")
            messagebox.showwarning(
                "Terminal Warning",
                "No standard Linux terminal emulator was found on your host system.\n"
                "Commands will execute, but opening separate terminal windows might require xterm/gnome-terminal."
            )
        else:
            self.log(f"Detected host terminal emulator: {self.terminal_emulator}", "SUCCESS")

        sshpass_path = shutil.which("sshpass")
        if not sshpass_path:
            self.log("NOTICE: 'sshpass' utility is not installed on host. SSH password authentication in terminal windows will require manual entry if keys are not configured.", "WARNING")
            self.log("To install sshpass for automated password login, run: sudo apt install -y sshpass", "INFO")
        else:
            self.log("Found 'sshpass' utility on host system.", "SUCCESS")

    # ---------------------------------------------------------
    # NETWORK & DEPLOYMENT ENGINE (THREADED)
    # ---------------------------------------------------------
    def test_connection(self):
        threading.Thread(target=self._test_connection_worker, daemon=True).start()

    def _test_connection_worker(self):
        mode = self.target_mode_var.get()
        user = self.username_var.get().strip()
        host = self.host_var.get().strip()
        password = self.password_var.get()
        port = self.port_var.get().strip()

        self.set_status("Testing connection...")
        self.log(f"Testing connection to target ({mode})...", "INFO")

        if mode == "SSH":
            if not host or not user:
                self.log("Host IP and Username are required for SSH test.", "ERROR")
                self.set_status("Connection Test Failed")
                return

            cmd = ["ssh", "-o", "ConnectTimeout=5", "-o", "StrictHostKeyChecking=no", "-p", port]
            if password and shutil.which("sshpass"):
                cmd = ["sshpass", "-p", password] + cmd + [f"{user}@{host}", "echo 'SSH Connection OK'"]
            else:
                cmd = cmd + [f"{user}@{host}", "echo 'SSH Connection OK'"]

            try:
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=8)
                if result.returncode == 0:
                    self.log(f"SUCCESS: Connected to remote SSH host {user}@{host}:{port}", "SUCCESS")
                    self.set_status("Connected to Target SSH Host")
                else:
                    err = result.stderr.strip() or result.stdout.strip()
                    self.log(f"ERROR: SSH Connection failed. {err}", "ERROR")
                    self.set_status("SSH Connection Failed")
            except Exception as e:
                self.log(f"ERROR: Exception while testing SSH: {str(e)}", "ERROR")
                self.set_status("Connection Error")

        else: # WSL Mode
            distro = host if host else "Ubuntu"
            cmd = ["wsl", "-d", distro, "bash", "-c", "echo 'WSL Connection OK'"]
            try:
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=8)
                if result.returncode == 0:
                    self.log(f"SUCCESS: Connected to WSL distro '{distro}'", "SUCCESS")
                    self.set_status(f"Connected to WSL ({distro})")
                else:
                    err = result.stderr.strip() or result.stdout.strip()
                    self.log(f"ERROR: WSL Connection failed. {err}", "ERROR")
                    self.set_status("WSL Connection Failed")
            except Exception as e:
                self.log(f"ERROR: Exception while testing WSL: {str(e)}", "ERROR")
                self.set_status("WSL Error")

    def copy_files_to_target(self):
        threading.Thread(target=self._copy_files_worker, daemon=True).start()

    def _copy_files_worker(self):
        mode = self.target_mode_var.get()
        user = self.username_var.get().strip()
        host = self.host_var.get().strip()
        password = self.password_var.get()
        port = self.port_var.get().strip()
        target_path = self.target_path_var.get().strip() or "~/GazeboManager"

        check_sh = os.path.join(self.script_dir, "check.sh")
        setup_sh = os.path.join(self.script_dir, "setup_gazebo.sh")

        if not os.path.exists(check_sh) or not os.path.exists(setup_sh):
            self.log(f"ERROR: Local files check.sh or setup_gazebo.sh not found in {self.script_dir}", "ERROR")
            return

        self.set_status("Deploying files to target...")
        self.log(f"Starting deployment of GazeboManager files to {target_path}...", "INFO")

        if mode == "SSH":
            if not host or not user:
                self.log("ERROR: Host IP and Username are required for SSH copy.", "ERROR")
                self.set_status("Deployment Failed")
                return

            # Step 1: Create target directory
            mkdir_cmd = ["ssh", "-o", "StrictHostKeyChecking=no", "-p", port]
            if password and shutil.which("sshpass"):
                mkdir_cmd = ["sshpass", "-p", password] + mkdir_cmd + [f"{user}@{host}", f"mkdir -p {target_path}"]
            else:
                mkdir_cmd = mkdir_cmd + [f"{user}@{host}", f"mkdir -p {target_path}"]

            res = subprocess.run(mkdir_cmd, capture_output=True, text=True)
            if res.returncode != 0:
                self.log(f"ERROR: Failed to create target directory {target_path}: {res.stderr.strip()}", "ERROR")
                self.set_status("Deployment Failed")
                return

            # Step 2: Copy files via SCP
            scp_cmd = ["scp", "-o", "StrictHostKeyChecking=no", "-P", port, check_sh, setup_sh]
            if password and shutil.which("sshpass"):
                scp_cmd = ["sshpass", "-p", password] + scp_cmd + [f"{user}@{host}:{target_path}/"]
            else:
                scp_cmd = scp_cmd + [f"{user}@{host}:{target_path}/"]

            self.log(f"Executing SCP copy to {user}@{host}:{target_path}...", "CMD")
            res_scp = subprocess.run(scp_cmd, capture_output=True, text=True)
            if res_scp.returncode != 0:
                self.log(f"ERROR: SCP transfer failed: {res_scp.stderr.strip()}", "ERROR")
                self.set_status("Deployment Failed")
                return

            # Step 3: Make executable
            chmod_cmd = ["ssh", "-o", "StrictHostKeyChecking=no", "-p", port]
            if password and shutil.which("sshpass"):
                chmod_cmd = ["sshpass", "-p", password] + chmod_cmd + [f"{user}@{host}", f"chmod +x {target_path}/*.sh"]
            else:
                chmod_cmd = chmod_cmd + [f"{user}@{host}", f"chmod +x {target_path}/*.sh"]

            subprocess.run(chmod_cmd, capture_output=True, text=True)

            self.log(f"SUCCESS: Successfully copied check.sh and setup_gazebo.sh to {user}@{host}:{target_path}/", "SUCCESS")
            self.set_status("Deployment Completed Successfully")

        else: # WSL Mode
            distro = host if host else "Ubuntu"
            # In WSL, copy files into distro path
            self.log(f"Copying files to WSL distro '{distro}'...", "CMD")
            wsl_mkdir = ["wsl", "-d", distro, "bash", "-c", f"mkdir -p {target_path}"]
            subprocess.run(wsl_mkdir, capture_output=True, text=True)

            wsl_copy_check = ["wsl", "-d", distro, "bash", "-c", f"cat > {target_path}/check.sh"]
            wsl_copy_setup = ["wsl", "-d", distro, "bash", "-c", f"cat > {target_path}/setup_gazebo.sh"]

            with open(check_sh, "r") as f:
                subprocess.run(wsl_copy_check, input=f.read(), text=True)
            with open(setup_sh, "r") as f:
                subprocess.run(wsl_copy_setup, input=f.read(), text=True)

            wsl_chmod = ["wsl", "-d", distro, "bash", "-c", f"chmod +x {target_path}/*.sh"]
            subprocess.run(wsl_chmod, capture_output=True, text=True)

            self.log(f"SUCCESS: Successfully copied files to WSL ({distro}):{target_path}/", "SUCCESS")
            self.set_status("Deployment to WSL Completed")

    # ---------------------------------------------------------
    # TERMINAL LAUNCHER ENGINE
    # ---------------------------------------------------------
    def launch_remote_command(self, remote_cmd, window_title="Gazebo Target Operation"):
        mode = self.target_mode_var.get()
        user = self.username_var.get().strip()
        host = self.host_var.get().strip()
        password = self.password_var.get()
        port = self.port_var.get().strip()
        target_path = self.target_path_var.get().strip() or "~/GazeboManager"

        term = self.terminal_emulator
        if not term:
            self.log("ERROR: No terminal emulator installed. Cannot open terminal window.", "ERROR")
            messagebox.showerror("Terminal Error", "No supported terminal emulator (gnome-terminal, xterm, etc.) found.")
            return

        self.log(f"Launching terminal window: '{window_title}' -> [{remote_cmd}]", "CMD")

        if mode == "SSH":
            if password and shutil.which("sshpass"):
                ssh_target_cmd = f"sshpass -p '{password}' ssh -t -o StrictHostKeyChecking=no -p {port} {user}@{host} \"cd {target_path} && {remote_cmd}; exec bash\""
            else:
                ssh_target_cmd = f"ssh -t -o StrictHostKeyChecking=no -p {port} {user}@{host} \"cd {target_path} && {remote_cmd}; exec bash\""

            if term == "gnome-terminal":
                full_term_cmd = ["gnome-terminal", f"--title={window_title}", "--", "bash", "-c", ssh_target_cmd]
            elif term == "xfce4-terminal":
                full_term_cmd = ["xfce4-terminal", f"--title={window_title}", "-e", f"bash -c \"{ssh_target_cmd}\""]
            elif term == "konsole":
                full_term_cmd = ["konsole", f"--title={window_title}", "-e", "bash", "-c", ssh_target_cmd]
            else: # xterm / tilix fallback
                full_term_cmd = [term, "-T", window_title, "-e", "bash", "-c", ssh_target_cmd]

        else: # WSL Mode
            distro = host if host else "Ubuntu"
            wsl_target_cmd = f"wsl -d {distro} bash -c \"cd {target_path} && {remote_cmd}; exec bash\""

            if term == "gnome-terminal":
                full_term_cmd = ["gnome-terminal", f"--title={window_title}", "--", "bash", "-c", wsl_target_cmd]
            elif term == "xfce4-terminal":
                full_term_cmd = ["xfce4-terminal", f"--title={window_title}", "-e", f"bash -c \"{wsl_target_cmd}\""]
            else:
                full_term_cmd = [term, "-T", window_title, "-e", "bash", "-c", wsl_target_cmd]

        try:
            subprocess.Popen(full_term_cmd)
            self.set_status(f"Launched terminal window: {window_title}")
        except Exception as e:
            self.log(f"ERROR launching terminal process: {str(e)}", "ERROR")

    # Specific preset actions
    def launch_sitl_plane(self):
        target_path = self.target_path_var.get().strip() or "~/GazeboManager"
        cmd = (
            "ARDU_DIR=$(python3 -c 'import os; print(os.path.expanduser(\"~/ardupilot\"))'); "
            "GZ_DIR=$(python3 -c 'import os; print(os.path.expanduser(\"~/ardupilot_gazebo\"))'); "
            "cd $ARDU_DIR && python3 Tools/autotest/sim_vehicle.py -v ArduPlane -f gazebo-zephyr "
            "--model JSON --add-param-file=$GZ_DIR/config/gazebo-zephyr-gimbal.parm --console --map"
        )
        self.launch_remote_command(cmd, "ArduPlane SITL Simulation")

    def launch_sitl_copter(self):
        cmd = (
            "ARDU_DIR=$(python3 -c 'import os; print(os.path.expanduser(\"~/ardupilot\"))'); "
            "GZ_DIR=$(python3 -c 'import os; print(os.path.expanduser(\"~/ardupilot_gazebo\"))'); "
            "cd $ARDU_DIR && python3 Tools/autotest/sim_vehicle.py -v ArduCopter -f gazebo-iris "
            "--model JSON --add-param-file=$GZ_DIR/config/gazebo-iris-gimbal.parm --console --map"
        )
        self.launch_remote_command(cmd, "ArduCopter SITL Simulation")

    def launch_gazebo_world(self):
        world = self.selected_world_var.get()
        cmd = (
            "GZ_DIR=$(python3 -c 'import os; print(os.path.expanduser(\"~/ardupilot_gazebo\"))'); "
            "export GZ_SIM_SYSTEM_PLUGIN_PATH=$GZ_DIR/build:$GZ_SIM_SYSTEM_PLUGIN_PATH; "
            "export GZ_SIM_RESOURCE_PATH=$GZ_DIR/models:$GZ_DIR/worlds:$GZ_SIM_RESOURCE_PATH; "
            f"gz sim -v4 -r {world}"
        )
        self.launch_remote_command(cmd, f"Gazebo Sim - {world}")

    def enable_video_stream(self):
        cmd = "gz topic -t /gimbal/camera/enable_streaming -m gz.msgs.Boolean -p \"data: 1\""
        self.launch_remote_command(cmd, "Enable Gimbal Video Stream")

    def launch_video_receiver(self):
        local_cmd = "ffplay -flags low_delay -fflags nobuffer udp://127.0.0.1:5600"
        self.log(f"Launching local stream receiver: [{local_cmd}]", "CMD")
        term = self.terminal_emulator
        if term == "gnome-terminal":
            subprocess.Popen(["gnome-terminal", "--title=Video Stream Receiver", "--", "bash", "-c", f"{local_cmd}; exec bash"])
        else:
            subprocess.Popen([term or "xterm", "-e", f"bash -c \"{local_cmd}; exec bash\""])


if __name__ == "__main__":
    app = GazeboManagerGUI()
    app.mainloop()
