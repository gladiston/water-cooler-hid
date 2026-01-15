#!/bin/bash
# install-user.sh
#
# Instalador (modo usuário) para o "CPU Cooler HID Display"
# - Verifica/instala dependências: python3-hid, python3-psutil, python3-pip, python-is-python3
# - Mostra lsusb filtrado (remove Linux Foundation)
# - Sugere VID/PID do cooler (prioriza ID aa88:8666)
# - Cria regra udev para permitir acesso ao hidraw sem precisar rodar o serviço como root
# - Instala o script Python em ~/.local/bin/cpu_cooler.py
# - Instala o serviço systemd --user em ~/.config/systemd/user/cpu-cooler.service
#
# Uso:
#   chmod +x install-user.sh
#   ./install-user.sh
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

pkg_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

ensure_pkg() {
  local pkg="$1"
  if pkg_installed "$pkg"; then
    echo "✔ Pacote já instalado: $pkg"
    return 0
  fi

  echo "📦 Pacote ausente: $pkg"
  echo "   Vou tentar instalar usando sudo (pode pedir sua senha)."
  sudo apt-get install -y "$pkg"
}

need_cmd lsusb
need_cmd dpkg
need_cmd apt-get
need_cmd systemctl
need_cmd python3

echo "🔎 Verificando dependências Python..."

# Atualiza índice só uma vez, se precisar instalar algo
NEED_UPDATE=0
for p in python3-hid python3-psutil python3-pip python-is-python3; do
  if ! pkg_installed "$p"; then
    NEED_UPDATE=1
    break
  fi
done

if [ "$NEED_UPDATE" -eq 1 ]; then
  echo "📦 Algumas dependências estão ausentes. Atualizando lista de pacotes (apt-get update)..."
  sudo apt-get update -y
fi

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

# 1) Preferência absoluta: ID aa88:8666 (se existir)
MATCH_LINE="$(echo "$LSUSB_OUTPUT" | grep -i 'ID aa88:8666' || true)"
if [ -n "$MATCH_LINE" ]; then
  SUGGEST_VENDOR="aa88"
  SUGGEST_PRODUCT="8666"
else
  # 2) Fallback por palavras-chave (não depende do chinês)
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
  echo "   VENDOR_ID (hex, sem 0x): $SUGGEST_VENDOR"
  echo "   PRODUCT_ID (hex, sem 0x): $SUGGEST_PRODUCT"
  echo ""
else
  echo ""
  echo "ℹ️  Não consegui sugerir automaticamente o VID/PID do cooler."
  echo "   Procure na lista acima a linha do seu dispositivo (ex: ID aa88:8666)."
  echo ""
fi

# Permite ENTER para aceitar o sugerido
read -p "Digite o VENDOR_ID do seu dispositivo (hex, sem 0x) [${SUGGEST_VENDOR}]: " VENDOR_ID
read -p "Digite o PRODUCT_ID do seu dispositivo (hex, sem 0x) [${SUGGEST_PRODUCT}]: " PRODUCT_ID

VENDOR_ID="$(normalize_hex "${VENDOR_ID:-$SUGGEST_VENDOR}")"
PRODUCT_ID="$(normalize_hex "${PRODUCT_ID:-$SUGGEST_PRODUCT}")"

if ! [[ "$VENDOR_ID" =~ ^[0-9a-f]{4}$ ]] || ! [[ "$PRODUCT_ID" =~ ^[0-9a-f]{4}$ ]]; then
  echo "❌ VENDOR_ID e PRODUCT_ID devem ter 4 dígitos hexadecimais (ex: aa88 / 8666)."
  exit 1
fi

echo ""
echo "🔧 Criando regra udev para hidraw (exige sudo)..."
UDEV_RULE_FILE="/etc/udev/rules.d/99-cpu-cooler-hid.rules"
UDEV_RULE_CONTENT="SUBSYSTEM==\"hidraw\", ATTRS{idVendor}==\"$VENDOR_ID\", ATTRS{idProduct}==\"$PRODUCT_ID\", MODE=\"0666\""
echo "$UDEV_RULE_CONTENT" | sudo tee "$UDEV_RULE_FILE" >/dev/null
sudo udevadm control --reload-rules
sudo udevadm trigger

echo ""
echo "📦 Instalando o script Python em ~/.local/bin/cpu_cooler.py ..."
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/cpu_cooler.py" <<'PYEOF'
#!/usr/bin/env python3
# cpu_cooler.py
#
# Envia a temperatura atual da CPU para o display de um water cooler via USB HID.
#
# Requisitos:
#   hidapi / psutil (via pacotes python3-hid e python3-psutil no Debian/Ubuntu)
#
# Notas:
# - Abre o dispositivo via path (hid.enumerate), mais robusto no Linux
# - dev.write() espera bytes/bytearray
# - Payload de 64 bytes (comum em HID)

import hid
import psutil
from threading import Event, Thread

VENDOR_ID = 0xaa88
PRODUCT_ID = 0x8666

def get_cpu_temp() -> float:
    temps = psutil.sensors_temperatures()

    if "k10temp" in temps and temps["k10temp"]:
        return temps["k10temp"][0].current

    for sensor_list in temps.values():
        if sensor_list:
            return sensor_list[0].current

    raise RuntimeError("Nenhum sensor de temperatura encontrado")

def open_device(vid: int, pid: int) -> hid.Device:
    for d in hid.enumerate(vid, pid):
        return hid.Device(path=d["path"])
    raise FileNotFoundError(f"Dispositivo HID não encontrado (vid={hex(vid)}, pid={hex(pid)})")

def write_to_cpu_fan_display(dev: hid.Device) -> None:
    try:
        cpu_temp = int(get_cpu_temp()) & 0xFF

        payload = bytearray(64)
        payload[0] = 0x00
        payload[1] = cpu_temp

        dev.write(bytes(payload))
        # Se quiser ver no console:
        # print(f"📤 Temperatura enviada: {cpu_temp}°C")
    except Exception as e:
        print(f"⚠️ Erro ao enviar dados: {e}")

def call_repeatedly(interval: float, func, *args):
    stopped = Event()

    def loop():
        while not stopped.wait(interval):
            func(*args)

    Thread(target=loop, daemon=True).start()
    return stopped.set

def main() -> int:
    try:
        dev = open_device(VENDOR_ID, PRODUCT_ID)
        print("✅ HID conectado via path")
    except Exception as e:
        print(f"❌ Erro ao abrir dispositivo HID: {e}")
        return 1

    cancel = call_repeatedly(1, write_to_cpu_fan_display, dev)

    try:
        while True:
            Event().wait(10)
    except KeyboardInterrupt:
        print("\n⏹️ Encerrando...")
        cancel()
        dev.close()
        return 0

if __name__ == "__main__":
    raise SystemExit(main())
PYEOF
chmod +x "$HOME/.local/bin/cpu_cooler.py"

echo ""
echo "🧩 Instalando o serviço systemd (usuário) ..."
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/cpu-cooler.service" <<'SVCEOF'
[Unit]
Description=CPU Cooler HID Display (Usuario)
After=default.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 %h/.local/bin/cpu_cooler.py
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
SVCEOF

echo ""
echo "🔄 Recarregando systemd (usuário), habilitando e iniciando o serviço..."
systemctl --user daemon-reload
systemctl --user enable cpu-cooler.service
systemctl --user restart cpu-cooler.service

echo ""
echo "✅ Instalação concluída (modo usuário)."
echo "📌 Status:"
echo "   systemctl --user status cpu-cooler.service"
echo ""
echo "Opcional (para iniciar mesmo sem login):"
echo "   sudo loginctl enable-linger $USER"
