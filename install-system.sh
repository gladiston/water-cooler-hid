#!/bin/bash
# install-system.sh
#
# Instalador (modo sistema) para o "CPU Cooler HID Display"
# - Verifica/instala dependências: python3-hid, python3-psutil, python3-pip, python-is-python3
# - Mostra lsusb filtrado (remove Linux Foundation)
# - Sugere VID/PID do cooler (prioriza ID aa88:8666)
# - Cria regra udev para permitir acesso ao hidraw
# - Instala o script Python em /usr/local/bin/cpu-cooler.py
# - Instala o serviço systemd em /etc/systemd/system/cpu-cooler.service
#
# Uso:
#   chmod +x install-system.sh
#   sudo ./install-system.sh
#
# Observação:
#   Informe VID/PID em hexadecimal sem "0x" (ex: aa88 / 8666)

set -e

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "❌ Comando obrigatório não encontrado: $1"
    exit 1
  fi
}

normalize_hex() {
  echo "$1" | sed 's/^0[xX]//' | tr '[:upper:]' '[:lower:]'
}

extract_vidpid() {
  echo "$1" | sed -n 's/.*ID \([0-9a-fA-F]\{4\}:[0-9a-fA-F]\{4\}\).*/\1/p'
}

ensure_pkg() {
  local pkg="$1"
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    echo "📦 Instalando pacote: $pkg"
    apt-get install -y "$pkg"
  else
    echo "✔ Pacote já instalado: $pkg"
  fi
}

# Checa root
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Este script deve ser executado como root. Use: sudo ./install-system.sh"
  exit 1
fi

need_cmd lsusb
need_cmd apt-get
need_cmd systemctl
need_cmd udevadm

echo "🔎 Verificando dependências Python..."
apt-get update -y
ensure_pkg python3-hid
ensure_pkg python3-psutil
ensure_pkg python3-pip
ensure_pkg python-is-python3

need_cmd python3

echo ""
echo "🔍 Dispositivos USB detectados (lsusb filtrado):"
echo "------------------------------------------------"
LSUSB_OUTPUT="$(lsusb | grep -v 'Linux Foundation' || true)"
echo "$LSUSB_OUTPUT"
echo "------------------------------------------------"

SUGGEST_VENDOR=""
SUGGEST_PRODUCT=""
MATCH_LINE=""

# 1) Preferência absoluta: ID aa88:8666
MATCH_LINE="$(echo "$LSUSB_OUTPUT" | grep -i 'ID aa88:8666' || true)"
if [ -n "$MATCH_LINE" ]; then
  SUGGEST_VENDOR="aa88"
  SUGGEST_PRODUCT="8666"
else
  # 2) Fallback por palavras-chave
  MATCH_LINE="$(echo "$LSUSB_OUTPUT" | grep -iE 'HID|温度|temperature|temp|display' | head -n 1 || true)"
  if [ -n "$MATCH_LINE" ]; then
    VIDPID="$(extract_vidpid "$MATCH_LINE")"
    if [ -n "$VIDPID" ]; then
      SUGGEST_VENDOR="$(echo "$VIDPID" | cut -d: -f1 | tr '[:upper:]' '[:lower:]')"
      SUGGEST_PRODUCT="$(echo "$VIDPID" | cut -d: -f2 | tr '[:upper:]' '[:lower:]')"
    fi
  fi
fi

if [ -n "$SUGGEST_VENDOR" ] && [ -n "$SUGGEST_PRODUCT" ]; then
  echo ""
  echo "⭐ Possível dispositivo do cooler encontrado:"
  echo "   $MATCH_LINE"
  echo ""
  echo "➡️  Parâmetros sugeridos (cooler):"
  echo "   Digite o VENDOR_ID (hex, sem 0x): $SUGGEST_VENDOR"
  echo "   Digite o PRODUCT_ID (hex, sem 0x): $SUGGEST_PRODUCT"
  echo ""
fi

read -p "Digite o VENDOR_ID do seu dispositivo (hex, sem 0x) [${SUGGEST_VENDOR}]: " VENDOR_ID
read -p "Digite o PRODUCT_ID do seu dispositivo (hex, sem 0x) [${SUGGEST_PRODUCT}]: " PRODUCT_ID

VENDOR_ID="$(normalize_hex "${VENDOR_ID:-$SUGGEST_VENDOR}")"
PRODUCT_ID="$(normalize_hex "${PRODUCT_ID:-$SUGGEST_PRODUCT}")"

if ! [[ "$VENDOR_ID" =~ ^[0-9a-f]{4}$ ]] || ! [[ "$PRODUCT_ID" =~ ^[0-9a-f]{4}$ ]]; then
  echo "❌ VENDOR_ID e PRODUCT_ID devem ter 4 dígitos hexadecimais (ex: aa88 / 8666)."
  exit 1
fi

echo ""
echo "🔧 Criando regra udev para hidraw..."
UDEV_RULE_FILE="/etc/udev/rules.d/99-cpu-cooler-hid.rules"
UDEV_RULE_CONTENT="SUBSYSTEM==\"hidraw\", ATTRS{idVendor}==\"$VENDOR_ID\", ATTRS{idProduct}==\"$PRODUCT_ID\", MODE=\"0666\""
echo "$UDEV_RULE_CONTENT" > "$UDEV_RULE_FILE"

udevadm control --reload-rules
udevadm trigger

echo ""
echo "📦 Instalando script Python em /usr/local/bin/cpu-cooler.py ..."
cat > /usr/local/bin/cpu-cooler.py <<'PYEOF'
#!/usr/bin/env python3
import hid
import psutil
from threading import Event, Thread

VENDOR_ID = 0xaa88
PRODUCT_ID = 0x8666

def get_cpu_temp():
    temps = psutil.sensors_temperatures()
    if "k10temp" in temps and temps["k10temp"]:
        return temps["k10temp"][0].current
    for sensor_list in temps.values():
        if sensor_list:
            return sensor_list[0].current
    raise RuntimeError("Nenhum sensor de temperatura encontrado")

def open_device(vid, pid):
    for d in hid.enumerate(vid, pid):
        return hid.Device(path=d["path"])
    raise FileNotFoundError("Dispositivo HID não encontrado")

def write_to_cpu_fan_display(dev):
    try:
        cpu_temp = int(get_cpu_temp()) & 0xFF
        payload = bytearray(64)
        payload[0] = 0x00
        payload[1] = cpu_temp
        dev.write(bytes(payload))
    except Exception as e:
        print(f"Erro ao enviar dados: {e}")

def call_repeatedly(interval, func, *args):
    stopped = Event()
    def loop():
        while not stopped.wait(interval):
            func(*args)
    Thread(target=loop, daemon=True).start()
    return stopped.set

def main():
    dev = open_device(VENDOR_ID, PRODUCT_ID)
    cancel = call_repeatedly(1, write_to_cpu_fan_display, dev)
    try:
        while True:
            Event().wait(10)
    except KeyboardInterrupt:
        cancel()
        dev.close()

if __name__ == "__main__":
    main()
PYEOF
chmod 0755 /usr/local/bin/cpu-cooler.py

echo ""
echo "🧩 Instalando serviço systemd em /etc/systemd/system/cpu-cooler.service ..."
cat > /etc/systemd/system/cpu-cooler.service <<'SVCEOF'
[Unit]
Description=CPU Cooler HID Display (System)
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/cpu-cooler.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
SVCEOF

echo ""
echo "🔄 Recarregando systemd, habilitando e iniciando o serviço..."
systemctl daemon-reload
systemctl enable cpu-cooler.service
systemctl restart cpu-cooler.service

echo ""
echo "✅ Instalação concluída (modo sistema)."
echo "📌 Status:"
echo "   systemctl status cpu-cooler.service"
