#!/bin/bash
# install-user.sh
#
# Instalador / Desinstalador (modo usuário) para o "CPU Cooler HID Display"
#
# Uso:
#   ./install-user.sh            -> instala
#   ./install-user.sh --uninstall -> desinstala
#
# A desinstalação remove:
#   - serviço systemd --user
#   - script Python do usuário
#   - NÃO remove a regra udev (compartilhada com instalação system-wide)

set -e

# ---------------- utilidades ----------------

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

# ---------------- modo uninstall ----------------

if [ "$1" = "--uninstall" ]; then
  echo "🗑️  Iniciando desinstalação (modo usuário)..."
  echo ""

  if systemctl --user list-unit-files | grep -q "^cpu-cooler.service"; then
    echo "⏹️  Parando e removendo serviço systemd --user..."
    systemctl --user stop cpu-cooler.service || true
    systemctl --user disable cpu-cooler.service || true
    rm -f "$HOME/.config/systemd/user/cpu-cooler.service"
    systemctl --user daemon-reload
  else
    echo "ℹ️  Serviço systemd --user não encontrado."
  fi

  if [ -f "$HOME/.local/bin/cpu_cooler.py" ]; then
    echo "🧹 Removendo script Python do usuário..."
    rm -f "$HOME/.local/bin/cpu_cooler.py"
  fi

  echo ""
  echo "✅ Desinstalação concluída (modo usuário)."
  echo "ℹ️  Observação: a regra udev NÃO foi removida."
  echo "   Caso deseje removê-la, use o install-system.sh --uninstall."
  exit 0
fi

# ---------------- checagens iniciais ----------------

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
lsusb | grep -v 'Linux Foundation' || true
echo "------------------------------------------------"

read -p "Digite o VENDOR_ID (hex, sem 0x) [aa88]: " VENDOR_ID
read -p "Digite o PRODUCT_ID (hex, sem 0x) [8666]: " PRODUCT_ID

VENDOR_ID="$(normalize_hex "${VENDOR_ID:-aa88}")"
PRODUCT_ID="$(normalize_hex "${PRODUCT_ID:-8666}")"

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
  echo "   é FIXO do hardware e NÃO pode ser alterado."
  echo ""
fi

echo ""
echo "📦 Instalando script Python do usuário..."
mkdir -p "$HOME/.local/bin"
cp cpu_cooler.py "$HOME/.local/bin/cpu_cooler.py" 2>/dev/null || true
chmod +x "$HOME/.local/bin/cpu_cooler.py"

echo ""
echo "🧩 Instalando serviço systemd --user..."
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
echo "✅ Instalação concluída (modo usuário)."
