#!/bin/bash
# install-user.sh
#
# Instalador (modo usuário) para o "CPU Cooler HID Display"
# Inclui aviso claro quando o modo escolhido não for temperatura,
# explicando que o texto "Temp/C" no display é fixo do hardware.

set -e

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "❌ Comando obrigatório não encontrado: $1"
    exit 1
  fi
}

pkg_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

ensure_pkg() {
  local pkg="$1"
  if pkg_installed "$pkg"; then
    echo "✔ Pacote já instalado: $pkg"
  else
    echo "📦 Instalando pacote ausente: $pkg"
    sudo apt-get install -y "$pkg"
  fi
}

normalize_hex() {
  echo "$1" | sed 's/^0[xX]//' | tr '[:upper:]' '[:lower:]'
}

extract_vidpid() {
  echo "$1" | sed -n 's/.*ID \([0-9a-fA-F]\{4\}:[0-9a-fA-F]\{4\}\).*/\1/p'
}

need_cmd lsusb
need_cmd dpkg
need_cmd apt-get
need_cmd systemctl
need_cmd python3

echo "🔎 Verificando dependências Python..."

NEED_UPDATE=0
for p in python3-hid python3-psutil python3-pip python-is-python3; do
  if ! pkg_installed "$p"; then
    NEED_UPDATE=1
    break
  fi
done

if [ "$NEED_UPDATE" -eq 1 ]; then
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

MATCH_LINE="$(echo "$LSUSB_OUTPUT" | grep -i 'ID aa88:8666' || true)"
if [ -n "$MATCH_LINE" ]; then
  SUGGEST_VENDOR="aa88"
  SUGGEST_PRODUCT="8666"
fi

if [ -n "$SUGGEST_VENDOR" ]; then
  echo ""
  echo "⭐ Possível dispositivo do cooler encontrado:"
  echo "   $MATCH_LINE"
  echo ""
fi

read -p "Digite o VENDOR_ID (hex, sem 0x) [${SUGGEST_VENDOR}]: " VENDOR_ID
read -p "Digite o PRODUCT_ID (hex, sem 0x) [${SUGGEST_PRODUCT}]: " PRODUCT_ID

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
  echo "   O texto exibido na linha inferior do cooler (ex: \"Temp/C\")"
  echo "   é FIXO do hardware e NÃO pode ser alterado pelo script."
  echo ""
  echo "   O valor mostrado estará correto, mas o texto não refletirá"
  echo "   o modo escolhido ($DISPLAY_MODE)."
  echo ""
fi

echo ""
echo "🔧 Criando regra udev para hidraw (exige sudo)..."
UDEV_RULE_FILE="/etc/udev/rules.d/99-cpu-cooler-hid.rules"
echo "SUBSYSTEM==\"hidraw\", ATTRS{idVendor}==\"$VENDOR_ID\", ATTRS{idProduct}==\"$PRODUCT_ID\", MODE=\"0666\"" | sudo tee "$UDEV_RULE_FILE" >/dev/null
sudo udevadm control --reload-rules
sudo udevadm trigger

echo ""
echo "📦 Instalando script Python..."
mkdir -p "$HOME/.local/bin"
cp cpu_cooler.py "$HOME/.local/bin/cpu_cooler.py" 2>/dev/null || true
chmod +x "$HOME/.local/bin/cpu_cooler.py"

echo ""
echo "🧩 Instalando serviço systemd (usuário)..."
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/cpu-cooler.service" <<EOF
[Unit]
Description=CPU Cooler HID Display (Usuario)
After=default.target

[Service]
ExecStart=/usr/bin/python3 %h/.local/bin/cpu_cooler.py --mode ${DISPLAY_MODE}
Restart=always

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable cpu-cooler.service
systemctl --user restart cpu-cooler.service

echo ""
echo "✅ Instalação concluída."
