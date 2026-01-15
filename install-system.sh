#!/bin/bash
# install-system.sh
#
# Instalador / Desinstalador (modo sistema) para o "CPU Cooler HID Display"
#
# Uso:
#   sudo ./install-system.sh            -> instala
#   sudo ./install-system.sh --uninstall -> desinstala
#
# A desinstalação remove:
#   - serviço systemd
#   - script Python
#   - regra udev

set -e

# ---------------- utilidades ----------------

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

# ---------------- checagem root ----------------

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Este script deve ser executado como root."
  echo "   Use: sudo ./install-system.sh"
  exit 1
fi

# ---------------- modo uninstall ----------------

if [ "$1" = "--uninstall" ]; then
  echo "🗑️  Iniciando desinstalação do CPU Cooler HID Display (modo sistema)..."
  echo ""

  if systemctl list-unit-files | grep -q "^cpu-cooler.service"; then
    echo "⏹️  Parando e removendo serviço systemd..."
    systemctl stop cpu-cooler.service || true
    systemctl disable cpu-cooler.service || true
    rm -f /etc/systemd/system/cpu-cooler.service
    systemctl daemon-reload
  else
    echo "ℹ️  Serviço systemd não encontrado."
  fi

  if [ -f /usr/local/bin/cpu-cooler.py ]; then
    echo "🧹 Removendo script Python..."
    rm -f /usr/local/bin/cpu-cooler.py
  fi

  if [ -f /etc/udev/rules.d/99-cpu-cooler-hid.rules ]; then
    echo "🧹 Removendo regra udev..."
    rm -f /etc/udev/rules.d/99-cpu-cooler-hid.rules
    udevadm control --reload-rules
    udevadm trigger
  fi

  echo ""
  echo "✅ Desinstalação concluída."
  exit 0
fi

# ---------------- instalação ----------------

need_cmd lsusb
need_cmd apt-get
need_cmd systemctl
need_cmd udevadm
need_cmd dpkg
need_cmd python3

echo "🔎 Verificando dependências Python..."
apt-get update -y
ensure_pkg python3-hid
ensure_pkg python3-psutil
ensure_pkg python3-pip
ensure_pkg python-is-python3

echo ""
echo "🔍 Dispositivos USB detectados (lsusb filtrado):"
echo "------------------------------------------------"
LSUSB_OUTPUT="$(lsusb | grep -v 'Linux Foundation' || true)"
echo "$LSUSB_OUTPUT"
echo "------------------------------------------------"

SUGGEST_VENDOR=""
SUGGEST_PRODUCT=""
MATCH_LINE=""

MATCH_LINE="$(echo "$LSUSB_OUTPUT" | grep -i 'ID aa88:8666' || true)"
if [ -n "$MATCH_LINE" ]; then
  SUGGEST_VENDOR="aa88"
  SUGGEST_PRODUCT="8666"
else
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
  echo "➡️  VID/PID sugeridos:"
  echo "   VENDOR_ID : $SUGGEST_VENDOR"
  echo "   PRODUCT_ID: $SUGGEST_PRODUCT"
  echo ""
fi

read -p "Digite o VENDOR_ID do seu dispositivo (hex, sem 0x) [${SUGGEST_VENDOR}]: " VENDOR_ID
read -p "Digite o PRODUCT_ID do seu dispositivo (hex, sem 0x) [${SUGGEST_PRODUCT}]: " PRODUCT_ID

VENDOR_ID="$(normalize_hex "${VENDOR_ID:-$SUGGEST_VENDOR}")"
PRODUCT_ID="$(normalize_hex "${PRODUCT_ID:-$SUGGEST_PRODUCT}")"

if ! [[ "$VENDOR_ID" =~ ^[0-9a-f]{4}$ ]] || ! [[ "$PRODUCT_ID" =~ ^[0-9a-f]{4}$ ]]; then
  echo "❌ VENDOR_ID e PRODUCT_ID devem ter 4 dígitos hexadecimais."
  exit 1
fi

echo ""
echo "📟 Escolha o modo de exibição do display:"
echo "  1) Temperatura da CPU (temp) [padrão]"
echo "  2) Uso da CPU em % (cpu)"
echo "  3) Uso da RAM em % (ram)"
echo ""
read -p "Selecione uma opção [1-3] (ENTER = padrão): " MODE_OPT

case "$MODE_OPT" in
  2) DISPLAY_MODE="cpu" ;;
  3) DISPLAY_MODE="ram" ;;
  ""|1) DISPLAY_MODE="temp" ;;
  *) echo "❌ Opção inválida."; exit 1 ;;
esac

echo "➡️  Modo selecionado: $DISPLAY_MODE"

if [ "$DISPLAY_MODE" != "temp" ]; then
  echo ""
  echo "⚠️  ATENÇÃO:"
  echo "   A linha inferior do display do cooler (ex: \"Temp/C\")"
  echo "   é um texto FIXO do hardware e NÃO pode ser alterado."
  echo ""
  echo "   O número exibido ficará correto, mas o texto abaixo"
  echo "   continuará mostrando \"Temp/C\"."
  echo ""
fi

echo ""
echo "🔧 Criando regra udev para hidraw..."
echo "SUBSYSTEM==\"hidraw\", ATTRS{idVendor}==\"$VENDOR_ID\", ATTRS{idProduct}==\"$PRODUCT_ID\", MODE=\"0666\"" \
  > /etc/udev/rules.d/99-cpu-cooler-hid.rules
udevadm control --reload-rules
udevadm trigger

echo ""
echo "📦 Instalando script Python em /usr/local/bin/cpu-cooler.py ..."
cat > /usr/local/bin/cpu-cooler.py <<'PYEOF'
#!/usr/bin/env python3
import hid
import psutil
import argparse
from threading import Event, Thread

VENDOR_ID = 0xaa88
PRODUCT_ID = 0x8666

def get_cpu_temp():
    temps = psutil.sensors_temperatures()
    if "k10temp" in temps and temps["k10temp"]:
        return int(temps["k10temp"][0].current)
    for sensor_list in temps.values():
        if sensor_list:
            return int(sensor_list[0].current)
    raise RuntimeError("Nenhum sensor de temperatura encontrado")

def get_cpu_percent():
    return int(psutil.cpu_percent(interval=0.2))

def get_ram_percent():
    return int(psutil.virtual_memory().percent)

def open_device(vid, pid):
    for d in hid.enumerate(vid, pid):
        return hid.Device(path=d["path"])
    raise FileNotFoundError("Dispositivo HID não encontrado")

def build_payload(value):
    payload = bytearray(64)
    payload[0] = 0x00
    payload[1] = value & 0xFF
    return bytes(payload)

def send_value(dev, mode):
    if mode == "cpu":
        value = get_cpu_percent()
    elif mode == "ram":
        value = get_ram_percent()
    else:
        value = get_cpu_temp()
    dev.write(build_payload(value))

def call_repeatedly(interval, func, *args):
    stopped = Event()
    def loop():
        while not stopped.wait(interval):
            func(*args)
    Thread(target=loop, daemon=True).start()
    return stopped.set

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", default="temp", choices=["temp","cpu","ram"])
    args = parser.parse_args()

    dev = open_device(VENDOR_ID, PRODUCT_ID)
    call_repeatedly(1, send_value, dev, args.mode)

    try:
        while True:
            Event().wait(10)
    except KeyboardInterrupt:
        dev.close()

if __name__ == "__main__":
    main()
PYEOF
chmod 0755 /usr/local/bin/cpu-cooler.py

echo ""
echo "🧩 Instalando serviço systemd em /etc/systemd/system/cpu-cooler.service ..."
cat > /etc/systemd/system/cpu-cooler.service <<SVCEOF
[Unit]
Description=CPU Cooler HID Display (System)
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/cpu-cooler.py --mode ${DISPLAY_MODE}
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
echo "📌 Modo configurado: ${DISPLAY_MODE}"
