#!/usr/bin/env bash
# xui-tunnelizer.sh – Interactive Reverse‑SSH + TLS Obfuscation
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
[[ $EUID -ne 0 ]] && { echo "❌ لطفاً به‌صورت root اجرا کنید"; exit 1; }

TUSER="xui"                    # نام کاربر روی سرور خارج
TLS_PORT_DEFAULT=443           # پورتی که ترافیک مخفی می‌شود
R_PORT_DEFAULT=22000           # پورت دور‌دست برای XUI
L_PORT_DEFAULT=10000           # پورت محلی XUI (روی سرور ایران)
STUNNEL_LCL=127.0.0.1:12345    # درگاه محلی برای SSH پشت stunnel

banner() { echo -e "\n\033[1;32m$*\033[0m"; }
ask() { read -rp "$1 " REPLY && echo "${REPLY:-$2}"; }

install_pkgs() { apt-get update -qq && apt-get install -yqq "$@"; }

###############################################################################
banner "🛠  این اسکریپت روی کدام سرور اجرا می‌شود؟"
PS3="انتخاب کنید (Ctrl‑C برای خروج): "
select MODE in "foreign (خارج)" "iran (داخل ایران)"; do
  [[ -n "$MODE" ]] && break
done

###############################################################################
if [[ $MODE == foreign* ]]; then
  banner "🚀 راه‌اندازی بخش «سرور خارج»"

  R_PORT=$(ask "➤ پورت remote برای XUI [${R_PORT_DEFAULT}]" "$R_PORT_DEFAULT")
  TLS_PORT=$(ask "➤ پورت TLS/HTTPS مخفی (443 به‌نظر عادی می‌آید) [${TLS_PORT_DEFAULT}]" "$TLS_PORT_DEFAULT")
  CERT_CN=$(ask "➤ دامنهٔ دلخواه برای گواهی (هر چیز معتبر مثل example.com)" "example.com")

  banner "🔧 نصب پکیج‌های لازم..."
  install_pkgs openssh-server autossh stunnel4

  banner "👤 ایجاد کاربر محدود '${TUSER}' (فقط تونل)"
  id -u "$TUSER" &>/dev/null || useradd -m -s /bin/bash "$TUSER"

  banner "🔑 تنظیم SSH برای Port‑Forward"
  sed -Ei 's/^#?GatewayPorts.*/GatewayPorts yes/' /etc/ssh/sshd_config
  sed -Ei 's/^#?AllowTcpForwarding.*/AllowTcpForwarding yes/' /etc/ssh/sshd_config
  systemctl restart ssh

  banner "📜 پیکربندی stunnel (server) روی پورت ${TLS_PORT}"
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
  sed -Ei 's/^ENABLED=.*/ENABLED=1/' /etc/default/stunnel4
  systemctl enable --now stunnel4

  banner "✅ سمت خارج کامل شد."
  echo "➜ حالا به سرور ایران بروید و همین اسکریپت را اجرا کنید (گزینه iran)."
  echo "   ▸ IP این سرور: $(curl -s ifconfig.me || hostname -I)"
  echo "   ▸ پورت TLS:    ${TLS_PORT}"
  echo "   ▸ پورت XUI:    ${R_PORT} (بعداً در XUI inbound ست می‌کنید)"
  exit 0
fi

###############################################################################
if [[ $MODE == iran* ]]; then
  banner "🌍 راه‌اندازی بخش «سرور داخل ایران»"

  FOREIGN_IP=$(ask "➤ IP سرور خارج؟" "")
  [[ -z $FOREIGN_IP ]] && { echo "IP نباید خالی باشد!"; exit 1; }
  TLS_PORT=$(ask "➤ پورت TLS روی سرور خارج [${TLS_PORT_DEFAULT}]" "$TLS_PORT_DEFAULT")
  R_PORT=$(ask "➤ پورت remote (همان که روی خارج تعیین کردید) [${R_PORT_DEFAULT}]" "$R_PORT_DEFAULT")
  L_PORT=$(ask "➤ پورت لوکال XUI روی ایران [${L_PORT_DEFAULT}]" "$L_PORT_DEFAULT")

  banner "🔧 نصب stunnel, autossh, netcat..."
  install_pkgs stunnel4 autossh openssh-client netcat-openbsd

  banner "📜 پیکربندی stunnel (client)"
  cat >/etc/stunnel/xui_client.conf <<EOF
client = yes
pid    = /var/run/stunnel_xui.pid
[ssh-tls]
accept  = ${STUNNEL_LCL}
connect = ${FOREIGN_IP}:${TLS_PORT}
EOF
  sed -Ei 's/^ENABLED=.*/ENABLED=1/' /etc/default/stunnel4
  systemctl enable --now stunnel4

  banner "🔑 تولید کلید و ارسال به خارج (از طریق stunnel)"
  ssh-keygen -q -t ed25519 -N "" -f /root/.ssh/id_xui_tunnel
  ssh-copy-id -i /root/.ssh/id_xui_tunnel.pub -p ${STUNNEL_LCL##*:} \
      "${TUSER}@127.0.0.1"

  banner "🚦 ساخت سرویس systemd برای AutoSSH"
  cat >/usr/local/bin/run-xui-tunnel <<EOF
#!/usr/bin/env bash
exec autossh -M 0 -N -o "ServerAliveInterval 30" -o "ServerAliveCountMax 5" \
  -p ${STUNNEL_LCL##*:} \
  -R ${R_PORT}:127.0.0.1:${L_PORT} ${TUSER}@127.0.0.1
EOF
  chmod +x /usr/local/bin/run-xui-tunnel

  cat >/etc/systemd/system/xui-tunnel.service <<EOF
[Unit]
Description=Reverse SSH Tunnel for XUI (obfuscated)
After=network.target stunnel4.service

[Service]
ExecStart=/usr/local/bin/run-xui-tunnel
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now xui-tunnel

  banner "✅ تمام شد!"
  cat <<INFO

🔹 حالا روی سرور خارج، پورت ${R_PORT} باز است (یا هر پورتی که در XUI inbound
     تعریف می‌کنید). اگر فایروال خارجی دارید، آن را باز کنید.

🔹 در پنل XUI یک «ورودی» (Inbound) از نوع VMess/VLESS بسازید:
     Address ➜ IP سرور *خارجی* (چون کلاینت‌ها مستقیم به آن می‌زنند)
     Port    ➜ ${R_PORT}

🔹 هر زمان بخواهید تنظیمات را عوض کنید:
     systemctl edit --full xui-tunnel.service
     systemctl restart xui-tunnel

🔒  کل ترافیک SSH شما داخل یک تونل TLS روی پورت ${TLS_PORT} پنهان است؛ از دید
     فیلترینگ مثل HTTPS معمولی به‌نظر می‌رسد و بلوک نمی‌شود.

موفق باشید ✌️
INFO
fi
