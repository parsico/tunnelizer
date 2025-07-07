#!/bin/bash
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" >&2
   sleep 1
   exit 1
fi

press_key() { read -p "Press any key to continue…"; }

# » ANSI colours & styles
purple="\033[35m"; green="\033[32m"; orange="\033[33m"; blue="\033[34m";
red="\033[31m"; cyan="\033[36m"; white="\033[37m"; reset="\033[0m";
bold="\033[1m"; underline="\033[4m"; normal="\033[0m";

colorize() {
  local colour_code style_code;
  case $1 in purple) colour_code=$purple;; green) colour_code=$green;; orange) colour_code=$orange;; blue) colour_code=$blue;; red) colour_code=$red;; cyan) colour_code=$cyan;; white) colour_code=$white;; *) colour_code=$reset;; esac;
  case ${3:-normal} in bold) style_code=$bold;; underline) style_code=$underline;; *) style_code=$normal;; esac;
  echo -e "${style_code}${colour_code}${2}${reset}";
}

# » Ensure required packages
install_pkg() {
  local pkg=$1;
  if ! command -v "$pkg" &>/dev/null; then
    if command -v apt-get &>/dev/null; then
      colorize orange "$pkg is not installed. Installing…" bold;
      sleep 1;
      apt-get update -qq; apt-get install -y "$pkg";
    else
      colorize red "Unsupported package manager — install $pkg manually." bold; press_key; exit 1;
    fi
  fi
}
install_pkg unzip
install_pkg curl
install_pkg jq

# » Globals
config_dir="/root/tunnelizer-core"
service_dir="/etc/systemd/system"

# » Download & install binary
download_and_extract_tunnelizer() {
  [[ -f "${config_dir}/tunnelizer" ]] && return 0;

  local DOWNLOAD_URL ARCH;
  ARCH=$(uname -m);
  case $ARCH in
    x86_64)    DOWNLOAD_URL="https://github.com/parsico/tunnelizer/releases/download/Tunnelizer/tunnelizer_linux_amd64.zip";;
    arm*)      DOWNLOAD_URL="https://github.com/parsico/tunnelizer/releases/download/Tunnelizer/tunnelizer_linux_arm.zip";;
    aarch64)   DOWNLOAD_URL="https://github.com/parsico/tunnelizer/releases/download/Tunnelizer/tunnelizer_linux_arm64.zip";;
    mips)      DOWNLOAD_URL="https://github.com/parsico/tunnelizer/releases/download/Tunnelizer/tunnelizer_linux_mips.zip";;
    mipsel)    DOWNLOAD_URL="https://github.com/parsico/tunnelizer/releases/download/Tunnelizer/tunnelizer_linux_mipsle.zip";;
    mips64)    DOWNLOAD_URL="https://github.com/parsico/tunnelizer/releases/download/Tunnelizer/tunnelizer_linux_mips64.zip";;
    mips64el)  DOWNLOAD_URL="https://github.com/parsico/tunnelizer/releases/download/Tunnelizer/tunnelizer_linux_mips64le.zip";;
    ppc64)     DOWNLOAD_URL="https://github.com/parsico/tunnelizer/releases/download/Tunnelizer/tunnelizer_linux_ppc64.zip";;
    ppc64le)   DOWNLOAD_URL="https://github.com/parsico/tunnelizer/releases/download/Tunnelizer/tunnelizer_linux_ppc64le.zip";;
    riscv64)   DOWNLOAD_URL="https://github.com/parsico/tunnelizer/releases/download/Tunnelizer/tunnelizer_linux_riscv64.zip";;
    s390x)     DOWNLOAD_URL="https://github.com/parsico/tunnelizer/releases/download/Tunnelizer/tunnelizer_linux_s390x.zip";;
    i386|i686) DOWNLOAD_URL="https://github.com/parsico/tunnelizer/releases/download/Tunnelizer/tunnelizer_linux_386.zip";;
    loong64)   DOWNLOAD_URL="https://github.com/parsico/tunnelizer/releases/download/Tunnelizer/tunnelizer_linux_loong64.zip";;
    *) colorize red "Unsupported architecture: $ARCH" bold; sleep 1; exit 1;;
  esac

  local DL; DL=$(mktemp -d);
  colorize blue "Downloading Tunnelizer…" bold; sleep 1;
  curl -sSL -o "$DL/tunnelizer.zip" "$DOWNLOAD_URL" || { colorize red "Download failed." bold; exit 1; };
  colorize blue "Extracting…" bold; sleep 1;
  mkdir -p "$config_dir";
  unzip -q "$DL/tunnelizer.zip" -d "$config_dir";
  chmod +x "${config_dir}/tunnelizer";
  [[ $(cat /proc/sys/net/ipv4/icmp_echo_ignore_all) -eq 0 ]] && echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_all;
  colorize green "Tunnelizer core installed successfully." bold;
  rm -rf "$DL";
}

# » Create launcher
install_launcher() {
  local launcher=/usr/local/bin/tunnelizer
  if [[ ! -f $launcher ]]; then
    cat > "$launcher" << 'LAUNCHER'
#!/bin/bash
exec bash <(curl -Ls https://raw.githubusercontent.com/parsico/tunnelizer/refs/heads/main/tunnelizer.sh)
LAUNCHER
    chmod +x "$launcher"
    colorize green "You can now run tunnelizer by typing: ${cyan}tunnelizer" bold;
  fi
}

# » UI: logo & info
display_logo() {
  echo -e "${purple}";
  cat << 'EOF'
████████╗██╗   ██╗███╗   ██╗███╗   ██╗███████╗██╗     ██╗███████╗███████╗██████╗ 
╚══██╔══╝██║   ██║████╗  ██║████╗  ██║██╔════╝██║     ██║╚══███╔╝██╔════╝██╔══██╗
   ██║   ██║   ██║██╔██╗ ██║██╔██╗ ██║█████╗  ██║     ██║  ███╔╝ █████╗  ██████╔╝
   ██║   ██║   ██║██║╚██╗██║██║╚██╗██║██╔══╝  ██║     ██║ ███╔╝  ██╔══╝  ██╔══██╗
   ██║   ╚██████╔╝██║ ╚████║██║ ╚████║███████╗███████╗██║███████╗███████╗██║  ██║
   ╚═╝    ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═══╝╚══════╝╚══════╝╚═╝╚══════╝╚══════╝╚═╝  ╚═╝
EOF
  colorize green "Version: ${orange}v1.0${reset}" bold;
  colorize green "GitHub: ${orange}github.com/parsico/tunnelizer${reset}" bold;
  colorize green "Telegram: ${orange}@PARSDADE${reset}" bold;
  colorize green "Official Site: ${orange}WWW.PARSICO.ORG${reset}" bold;
}

display_server_info() {
  local SERVER_IP SERVER_COUNTRY SERVER_ISP;
  SERVER_IP=$(hostname -I | awk '{print $1}');
  SERVER_COUNTRY=$(curl --max-time 3 -sS "http://ipwhois.app/json/$SERVER_IP" | jq -r '.country' 2>/dev/null || echo "Unknown");
  SERVER_ISP=$(curl --max-time 3 -sS "http://ipwhois.app/json/$SERVER_IP" | jq -r '.isp' 2>/dev/null || echo "Unknown");
  colorize cyan "═════════════════════════════════════════════";
  colorize cyan "Location   : ${green}${SERVER_COUNTRY}${cyan}";
  colorize cyan "Datacenter : ${green}${SERVER_ISP}${cyan}";
}

display_tunnelizer_status() {
  if [[ -f "${config_dir}/tunnelizer" ]]; then
    colorize cyan "Tunnelizer Core: ${green}Installed${cyan}";
  else
    colorize cyan "Tunnelizer Core: ${red}Not installed${cyan}";
  fi
  colorize cyan "═════════════════════════════════════════════";
}

check_port() {
  local port=$1;
  if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -gt 1024 ] && [ "$port" -le 65535 ]; then
    if ss -tln | grep -q ":$port " ; then
      colorize red "Port $port is already in use." bold; return 1;
    else return 0; fi;
  else
    colorize red "Invalid port 1025–65535 only." bold; return 1;
  fi
}

configure_tunnel() {
  [[ ! -f "${config_dir}/tunnelizer" ]] && { colorize red "Tunnelizer core missing. Install first." bold; press_key; return 1; };
  clear; colorize blue "Configure Tunnelizer" bold; echo;
  colorize green "1) Iran node (client)" bold;
  colorize green "2) Kharej node (server)" bold; echo;
  read -p "Enter choice [1/2]: " choice;
  case $choice in
    1) iran_server_configuration;;
    2) kharej_server_configuration;;
    *) colorize red "Invalid option." bold; sleep 1;;
  esac; press_key;
}

iran_server_configuration() {
  clear; colorize blue "Iran Node Setup" bold; echo;
  local kharej_ip tunnel_port;
  while true; do
    read -p "[*] Kharej server IP: " kharej_ip;
    [[ "$kharej_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && break || colorize red "Invalid IPv4." bold;
  done;
  while true; do
    read -p "[*] Desired local tunnel port: " tunnel_port;
    check_port "$tunnel_port" && break;
  done;
  cat > "${service_dir}/tunnelizer-iran${tunnel_port}.service" << EOF
[Unit]
Description=Tunnelizer Iran Client (Port $tunnel_port)
After=network.target

[Service]
Type=simple
ExecStart=${config_dir}/tunnelizer -type client -l :${tunnel_port} -s ${kharej_ip} -t 127.0.0.1:${tunnel_port} -tcp 1
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload >/dev/null 2>&1;
  systemctl enable --now "tunnelizer-iran${tunnel_port}.service" >/dev/null 2>&1 && \
    colorize green "Client tunnel on :$tunnel_port started." bold || \
    colorize red "Failed starting client tunnel!" bold;
}

kharej_server_configuration() {
  clear; colorize blue "Kharej Node Setup" bold; echo;
  cat > "${service_dir}/tunnelizer-kharej.service" << EOF
[Unit]
Description=Tunnelizer Kharej Server
After=network.target

[Service]
Type=simple
ExecStart=${config_dir}/tunnelizer -type server
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload >/dev/null 2>&1;
  systemctl enable --now "tunnelizer-kharej.service" >/dev/null 2>&1 && \
    colorize green "Kharej server service started." bold || \
    colorize red "Failed to start Kharej server service." bold;
}

check_tunnel_status() {
  clear; colorize blue "Tunnel Status" bold; echo;
  local found=0;
  for service in $(systemctl list-units --type=service | grep tunnelizer | awk '{print $1}'); do
    found=1;
    systemctl is-active --quiet "$service" && colorize green "$service is running" bold || colorize red "$service is NOT running" bold;
  done;
  [[ $found -eq 0 ]] && colorize red "No Tunnelizer services found." bold;
  press_key;
}

tunnel_management() {
  clear; colorize blue "Tunnel Management" bold; echo;
  local services=( $(systemctl list-units --type=service | grep tunnelizer | awk '{print $1}') );
  local idx=1;
  for svc in "${services[@]}"; do echo -e "${cyan}${idx}${reset}) ${green}${svc}${reset}"; ((idx++)); done
  [[ ${#services[@]} -eq 0 ]] && { colorize red "No services." bold; press_key; return 1; };
  echo; read -p "Select service (0 return): " ch;
  [[ $ch == 0 ]] && return;
  [[ $ch =~ ^[0-9]+$ ]] && (( ch>=1 && ch<=${#services[@]} )) || { colorize red "Invalid choice" bold; sleep 1; return; };
  local svc="${services[$((ch-1))]}"; clear; colorize blue "Manage $svc" bold; echo;
  colorize green "1) Restart" bold;
  colorize red "2) Stop" bold;
  colorize red "3) Delete" bold;
  colorize cyan "4) Logs" bold;
  colorize cyan "5) Status" bold; echo;
  read -p "Action [0‑5]: " act;
  case $act in
    1) systemctl restart "$svc"; colorize green "Restarted." bold;;
    2) systemctl stop "$svc"; colorize red "Stopped." bold;;
    3) systemctl disable --now "$svc" >/dev/null 2>&1; rm -f "${service_dir}/${svc}"; systemctl daemon-reload; colorize red "Deleted." bold;;
    4) journalctl -eu "$svc";;
    5) systemctl status "$svc";;
    *) colorize red "Invalid." bold;;
  esac;
  press_key;
}

remove_core() {
  clear; colorize blue "Remove Tunnelizer Core" bold; echo;
  if ls "$service_dir"/tunnelizer-*.service &>/dev/null; then
    colorize red "Active Tunnelizer services exist — delete them first." bold; press_key; return 1;
  fi;
  read -p "Remove core? (y/n): " confirm; [[ $confirm =~ ^[yY]$ ]] || { colorize orange "Cancelled." bold; press_key; return; };
  rm -rf "$config_dir" && colorize green "Core removed." bold || colorize red "Core folder missing." bold;
  press_key;
}

display_menu() {
  clear; display_logo; display_server_info; display_tunnelizer_status; echo;
  colorize green   "1. Configure new tunnel" bold;
  colorize red     "2. Tunnel management" bold;
  colorize cyan    "3. Check tunnels status" bold;
  colorize orange  "4. Install Tunnelizer core" bold;
  colorize red     "5. Remove Tunnelizer core" bold;
  colorize white   "0. Exit" bold; echo; echo "-------------------------------";
}

read_option() {
  read -p "Enter choice [0/5]: " choice;
  case $choice in
    1) configure_tunnel;;
    2) tunnel_management;;
    3) check_tunnel_status;;
    4) download_and_extract_tunnelizer;;
    5) remove_core;;
    0) exit 0;;
    *) colorize red "Invalid option" bold; sleep 1;;
  esac
}

# » Init
download_and_extract_tunnelizer
install_launcher

# » Start menu
while true; do display_menu; read_option; done
