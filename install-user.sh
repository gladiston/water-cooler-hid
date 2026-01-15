#!/bin/bash
# install-user.sh
#
# Instalador / Desinstalador (modo usuário) para o "CPU Cooler HID Display"
#
# Uso:
#   ./install-user.sh             -> instala
#   ./install-user.sh --uninstall -> desinstala
#
# Observação importante:
# - Este script DEVE ser executado como usuário normal (SEM sudo).
# - Ele usa sudo apenas onde precisa (regra udev).
# - Para registrar o serviço com "systemctl --user", é necessário que exista
#   uma sessão de usuário com systemd/DBus (variáveis XDG_RUNTIME_DIR e
#   DBUS_SESSION_BUS_ADDRESS). Em ambientes sem sessão (ex.: sudo, cron,
#   shell "su", etc.) ele instala os arquivos, mas pode NÃO conseguir
#   habilitar/iniciar o serviço automaticamente — nesse caso ele mostra o
#   comando para você rodar depois, já logado como o usuário.

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

  # Tenta remover usando systemctl --user se houver sessão
  if command -v systemctl >/dev/null 2>&1; then
    if [ -n "${XDG_RUNTIME_DIR:-}" ] || [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
      systemctl --user stop cpu-cooler.service 2>/dev/null || true
      systemctl --user disable cpu-cooler.service 2>/dev/null || true
      systemctl --user daemon-reload 2>/dev/null || true
    fi
  fi

  rm -f "$HOME/.config/systemd/user/cpu-cooler.service"
  rm -f "$HOME/.local/bin/cpu_cooler.py"

  echo "✅ Desinstalação concluída (modo usuário)."
  echo "ℹ️  Observação: a regra udev NÃO foi removida."
  echo "   Caso deseje removê-la, use o install-system.sh --uninstall."
  exit 0
fi

# ---------------- checagens iniciais ----------------

if [ "$(id -u)" -eq 0 ]; then
  echo "❌ Não execute este script com sudo/root."
  echo "   Rode como usuário normal: ./install-user.sh"
  echo "   (ele pede sudo só quando precisa criar a regra udev)"
  exit 1
fi

need_cmd lsusb
need_cmd dpkg
need_cmd apt-get
need_cmd python3
need_cmd systemctl

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

# Para o seu cooler mais comum
read -p "Digite o VENDOR_ID (hex, sem 0x) [aa88]: " VENDOR_ID
read -p "Digite o PRODUCT_ID (hex, sem 0x) [8666]: " PRODUCT_ID

VENDOR_ID="$(normalize_hex "${VENDOR_ID:-aa88}")"
PRODUCT_ID="$(normalize_hex "${PRODUCT_ID:-8666}")"

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
  echo "   A linha inferior do display do cooler (ex: \"Temp/C\")"
  echo "   é um texto FIXO do hardware e NÃO pode ser alterado."
  echo ""
  echo "   O número exibido ficará correto, mas o texto abaixo continuará"
  echo "   mostrando \"Temp/C\", mesmo no modo ${DISPLAY_MODE}."
  echo ""
fi

echo ""
echo "🔧 Criando regra udev para hidraw (exige sudo)..."
UDEV_RULE_FILE="/etc/udev/rules.d/99-cpu-cooler-hid.rules"
echo "SUBSYSTEM==\"hidraw\", ATTRS{idVendor}==\"$VENDOR_ID\", ATTRS{idProduct}==\"$PRODUCT_ID\", MODE=\"0666\"" \
  | sudo tee "$UDEV_RULE_FILE" >/dev/null
sudo udevadm control --reload-rules
sudo udevadm trigger

echo ""
echo "📦 Instalando script Python do usuário em ~/.local/bin/cpu_cooler.py ..."
mkdir -p "$HOME/.local/bin"
# O arquivo cpu_cooler.py deve estar na mesma pasta do instalador
if [ ! -f "./cpu_cooler.py" ]; then
  echo "❌ Não encontrei ./cpu_cooler.py no diretório atual."
  echo "   Rode o instalador dentro da pasta do projeto, onde está o cpu_cooler.py."
  exit 1
fi
cp "./cpu_cooler.py" "$HOME/.local/bin/cpu_cooler.py"
chmod +x "$HOME/.local/bin/cpu_cooler.py"

echo ""
echo "🧩 Instalando serviço systemd --user..."
mkdir -p "$HOME/.config/systemd/user"
cat > "$HOME/.config/systemd/user/cpu-cooler.service" <<EOF
[Unit]
Description=CPU Cooler HID Display (Usuario)
After=default.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 %h/.local/bin/cpu_cooler.py --mode ${DISPLAY_MODE}
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
EOF

echo ""
echo "🔄 Registrando serviço no systemd --user..."

set +e
systemctl --user daemon-reload 2>/dev/null
RC1=$?
systemctl --user enable cpu-cooler.service 2>/dev/null
RC2=$?
systemctl --user restart cpu-cooler.service 2>/dev/null
RC3=$?
set -e

if [ "$RC1" -ne 0 ] || [ "$RC2" -ne 0 ] || [ "$RC3" -ne 0 ]; then
  echo ""
  echo "⚠️  Não consegui conectar no \"systemd --user\" nesta sessão."
  echo "   Isso acontece quando você roda fora de uma sessão de usuário com DBus,"
  echo "   por exemplo: via sudo, cron, \"su\", ou terminal sem login."
  echo ""
  echo "✅ Os arquivos já foram instalados. Para habilitar/iniciar depois, faça login"
  echo "   normalmente como este usuário e execute:"
  echo ""
  echo "   systemctl --user daemon-reload"
  echo "   systemctl --user enable cpu-cooler.service"
  echo "   systemctl --user restart cpu-cooler.service"
  echo ""
  echo "Dica (opcional): para iniciar mesmo sem login, habilite linger:"
  echo "   sudo loginctl enable-linger $USER"
  echo ""
else
  echo "✅ Serviço instalado e iniciado com sucesso (systemd --user)."
fi

echo ""
echo "✅ Instalação concluída (modo usuário)."
