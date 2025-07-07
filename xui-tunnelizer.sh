#!/usr/bin/env bash
# xui‑tunnelizer.sh – v2025‑07‑07‑fix1
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
[[ $EUID -ne 0 ]] && { echo "❌ لطفاً اسکریپت را به‌صورت root اجرا کنید"; exit 1; }

### پارامترهای قابل شخصی‌سازی
TUSER="xui"
TLS_PORT_DEFAULT=443
R_PORT_DEFAULT=22000
L_PORT_DEFAULT=10000
STUNNEL_LCL=127.0.0.1:12345        # <IP>:<Port> لوکال برای SSH پشت TLS
#####################################################################

banner() { echo -e "\n\033[1;36m$*\033[0m"; }
ask() { read -rp "$1 " _r; echo "${_r:-$2}"; }
install_pkgs(){ apt-get update -qq; apt-get install -yqq "$@"; }

banner "🛠  این سرور درون ایران است یا خارج؟"
PS3="انتخاب (Ctrl‑C خروج): "
select MODE in "foreign (خارج)" "iran (داخل ایران)"; do [[ $MODE ]] && break; done

########################################################################
if [[ $MODE == foreign* ]]; then
  banner "🚀 نصب بخش خارج از ایران"
  R_PORT=$(ask "➤ پورت remote برای XUI [$R_PORT_DEFAULT]" "$R_PORT_DEFAULT")
  TLS_PORT=$(ask "➤ پورت TLS/HTTPS مخفی [$TLS_PORT_DEFAULT]" "$TLS_PORT_DEFAULT")
  CERT_CN=$(ask "➤ دامنهٔ نمایشی گواهی (مثلاً example.com)" "example.com")

  banner "🔧 پیش‌نیازها"
  install_pkgs openssh-server autossh stunnel4 openssl ufw

  # کاربر محدود تونل
  id -u "$TUSER" &>/dev/null || useradd -m -s /usr/sbin/nologin "$TUSER"

  # اجازهٔ فوروارد در sshd
  sed -Ei 's/^#?GatewayPorts.*/GatewayPorts yes/' /etc/ssh/sshd_config
  sed -Ei 's/^#?AllowTcpForwarding.*/AllowTcpForwarding yes/' /etc/ssh/sshd_config
  systemctl restart ssh

  # stunnel server
  cat >/etc/stunnel/xui_server.conf <<EOF
cert = /etc/stunnel/xui.pem
pid  = /var/run/stunnel_xui.pid
setuid = stunnel4
setgid = stunnel4
[ssh-tls]
accept  = ${TLS_PORT}
connect = 127.0.0.1:22
EOF

  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
      -subj "/CN=${CERT_CN}" \
      -keyout /etc/stunnel/xui.key -out /etc/stunnel/xui.crt
  cat /etc/stunnel/xui.crt /etc/stunnel/xui.key > /etc/stunnel/xui.pem
  chmod 600 /etc/stunnel/xui.pem

  # فعال‌سازی stunnel
  sed -Ei 's/^ENABLED=.*/ENABLED=1/' /etc/default/stunnel4
  echo 'FILES="/etc/stunnel/xui_server.conf"' >> /etc/default/stunnel4
  systemctl enable --now stunnel4

  # باز کردن فایروال
  if ufw status | grep -q "Status: active"; then
    ufw allow "${TLS_PORT}/tcp"
    ufw allow "${R_PORT}/tcp"
  fi

  banner "✅ خارج آماده است."
  echo "- IP این سرور: $(curl -s ifconfig.me || hostname -I)"
  echo "- پورت TLS:     ${TLS_PORT}"
  echo "- پورت XUI:     ${R_PORT}"
  exit 0
fi

########################################################################
if [[ $MODE == iran* ]]; then
  banner "🌍 نصب بخش داخل ایران"

  FOREIGN_IP=$(ask "➤ IP سرور خارج؟" "")
  [[ -z $FOREIGN_IP ]] && { echo "IP خالی است!"; exit 1; }
  TLS_PORT=$(ask "➤ پورت TLS سرور خارج [$TLS_PORT_DEFAULT]" "$TLS_PORT_DEFAULT")
  R_PORT=$(ask "➤ پورت remote (همان روی خارج) [$R_PORT_DEFAULT]" "$R_PORT_DEFAULT")
  L_PORT=$(ask "➤ پورت لوکال XUI این سرور [$L_PORT_DEFAULT]" "$L_PORT_DEFAULT")

  banner "🔧 پیش‌نیاز‌ها"
  install_pkgs stunnel4 autossh openssh-client netcat-openbsd ufw

  # stunnel client
  cat >/etc/stunnel/xui_client.conf <<EOF
client = yes
pid    = /var/run/stunnel_xui.pid
[ssh-tls]
accept  = ${STUNNEL_LCL}
connect = ${FOREIGN_IP}:${TLS_PORT}
EOF
  sed -Ei 's/^ENABLED=.*/ENABLED=1/' /etc/default/stunnel4
  echo 'FILES="/etc/stunnel/xui_client.conf"' >> /etc/default/stunnel4
  systemctl enable --now stunnel4

  banner "🔑 انتقال کلید SSH پشت stunnel"
  ssh-keygen -q -t ed25519 -N "" -f /root/.ssh/id_xui_tunnel
  ssh-copy-id -i /root/.ssh/id_xui_tunnel.pub \
      -p "${STUNNEL_LCL##*:}" \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      "${TUSER}@127.0.0.1"

  # AutoSSH service
  cat >/usr/local/bin/run-xui-tunnel <<EOF
#!/usr/bin/env bash
exec autossh -M 0 -N \\
  -o "ServerAliveInterval 30" -o "ServerAliveCountMax 5" \\
  -o "ExitOnForwardFailure=yes" \\
  -p "${STUNNEL_LCL##*:}" \\
  -R "${R_PORT}:127.0.0.1:${L_PORT}" \\
  ${TUSER}@127.0.0.1
EOF
  chmod +x /usr/local/bin/run-xui-tunnel

  cat >/etc/systemd/system/xui-tunnel.service <<EOF
[Unit]
Description=Obfuscated Reverse SSH Tunnel for XUI
After=network.target stunnel4.service

[Service]
ExecStart=/usr/local/bin/run-xui-tunnel
Restart=always
RestartSec=8

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now xui-tunnel

  # باز کردن فایروال محلی برای XUI داخلی
  if ufw status | grep -q "Status: active"; then
    ufw allow "${L_PORT}/tcp"
  fi

  banner "✅ همه‌چیز اوکی شد!"
  cat <<INFO
▪️ حالا روی سرور *خارجی*، پورت ${R_PORT} باز است و Clientها مستقیم به همان می‌زنند  
▪️ در پنل XUI (روی خارج) Inbound بسازید: Address = سرور خارج، Port = ${R_PORT}  
▪️ سرویس‌ها را چک کنید:
   journalctl -u stunnel4 -u xui-tunnel -f
INFO
fi
