#!/bin/bash
# install-system.sh
#
# Uso:
#   sudo ./install-system.sh              -> instala
#   sudo ./install-system.sh --uninstall  -> desinstala
#
# Esta versão instala um cpu-cooler.py compatível com hid.Device OU hid.device().

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

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Este script deve ser executado como root."
  echo "   Use: sudo ./install-system.sh"
  exit 1
fi

if [ "$1" = "--uninstall" ]; then
  echo "🗑️  Iniciando desinstalação (modo sistema)..."
  systemctl stop cpu-cooler.service 2>/dev/null || true
  systemctl disable cpu-cooler.service 2>/dev/null || true
  rm -f /etc/systemd/system/cpu-cooler.service
  systemctl daemon-reload

  rm -f /usr/local/bin/cpu-cooler.py

  if [ -f /etc/udev/rules.d/99-cpu-cooler-hid.rules ]; then
    rm -f /etc/udev/rules.d/99-cpu-cooler-hid.rules
    udevadm control --reload-rules
    udevadm trigger
  fi

  echo "✅ Desinstalação concluída."
  exit 0
fi

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

VENDOR_ID="$(normalize_hex "${VENDOR_ID:-${SUGGEST_VENDOR}}")"
PRODUCT_ID="$(normalize_hex "${PRODUCT_ID:-${SUGGEST_PRODUCT}}")"

if ! [[ "$VENDOR_ID" =~ ^[0-9a-f]{4}$ ]] || ! [[ "$PRODUCT_ID" =~ ^[0-9a-f]{4}$ ]]; then
  echo "❌ VENDOR_ID e PRODUCT_ID devem ter 4 dígitos hexadecimais (ex: aa88 / 8666)."
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
  echo "   A linha inferior do display do cooler (ex: \"Temp/C\") é FIXA do hardware"
  echo "   e NÃO pode ser alterada pelo script."
  echo ""
fi

echo ""
echo "🔧 Criando regra udev para hidraw..."
echo "SUBSYSTEM==\"hidraw\", ATTRS{idVendor}==\"$VENDOR_ID\", ATTRS{idProduct}==\"$PRODUCT_ID\", MODE=\"0666\""   > /etc/udev/rules.d/99-cpu-cooler-hid.rules
udevadm control --reload-rules
udevadm trigger

echo ""
echo "📦 Instalando cpu-cooler.py compatível em /usr/local/bin/cpu-cooler.py ..."
cat > /usr/local/bin/cpu-cooler.py <<'PYEOF'
#!/usr/bin/env python3
import argparse
import sys
import time
import hid
import psutil

# Observacao:
# Este display aceita apenas um valor numerico (0-255). O texto/rotulo (ex: "Temp/C") e fixo do hardware.

def get_cpu_temp() -> int:
    temps = psutil.sensors_temperatures() or {}
    for key in ("k10temp", "coretemp"):
        if key in temps and temps[key]:
            return int(temps[key][0].current)
    for sensor_list in temps.values():
        if sensor_list:
            return int(sensor_list[0].current)
    raise RuntimeError("Nenhum sensor de temperatura encontrado via psutil.sensors_temperatures()")

def get_cpu_percent() -> int:
    return int(psutil.cpu_percent(interval=0.2))

def get_ram_percent() -> int:
    return int(psutil.virtual_memory().percent)

def build_payload(value: int) -> bytes:
    payload = bytearray(64)
    payload[0] = 0x00
    payload[1] = value & 0xFF
    return bytes(payload)

def open_device(vid: int, pid: int):
    # Compatibilidade com diferentes wrappers do 'hid':
    # - Alguns expõem hid.Device(path=...)
    # - Outros expõem hid.device() + open_path(...)
    devs = hid.enumerate(vid, pid) or []
    if not devs:
        raise FileNotFoundError(f"Nenhum dispositivo HID encontrado para VID:PID {vid:04x}:{pid:04x}")

    path = devs[0].get("path")
    if not path:
        raise RuntimeError("Dispositivo encontrado, mas sem 'path' no enumerate()")

    # 1) API "nova": hid.Device
    if hasattr(hid, "Device"):
        return hid.Device(path=path)

    # 2) API "antiga": hid.device()
    if hasattr(hid, "device"):
        d = hid.device()
        d.open_path(path)
        return d

    raise AttributeError("Modulo 'hid' nao expoe Device nem device(). Verifique o pacote instalado.")

def log(msg: str):
    print(msg, file=sys.stderr, flush=True)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--vid", default="aa88", help="VENDOR_ID em hex (sem 0x). Ex: aa88")
    parser.add_argument("--pid", default="8666", help="PRODUCT_ID em hex (sem 0x). Ex: 8666")
    parser.add_argument("--mode", default="temp", choices=["temp", "cpu", "ram"])
    parser.add_argument("--interval", type=float, default=1.0, help="Intervalo em segundos (padrao: 1.0)")
    args = parser.parse_args()

    try:
        vid = int(args.vid, 16)
        pid = int(args.pid, 16)
    except ValueError:
        raise SystemExit("VID/PID invalidos. Use hex sem 0x. Ex: --vid aa88 --pid 8666")

    dev = None

    while True:
        try:
            if dev is None:
                dev = open_device(vid, pid)
                log(f"✅ HID conectado: {vid:04x}:{pid:04x}")

            if args.mode == "cpu":
                value = get_cpu_percent()
            elif args.mode == "ram":
                value = get_ram_percent()
            else:
                value = get_cpu_temp()

            dev.write(build_payload(value))
            time.sleep(args.interval)

        except KeyboardInterrupt:
            break
        except Exception as e:
            log(f"⚠ Erro: {type(e).__name__}: {e} (vou tentar novamente em 2s)")
            try:
                if dev is not None:
                    dev.close()
            except Exception:
                pass
            dev = None
            time.sleep(2)

    try:
        if dev is not None:
            dev.close()
    except Exception:
        pass

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
ExecStart=/usr/bin/python3 /usr/local/bin/cpu-cooler.py --vid $VENDOR_ID --pid $PRODUCT_ID --mode $DISPLAY_MODE
Restart=always
RestartSec=2
StandardOutput=journal
StandardError=journal

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
echo "📌 Modo configurado: $DISPLAY_MODE"
echo "📌 Ver logs:"
echo "   journalctl -u cpu-cooler.service -f"
