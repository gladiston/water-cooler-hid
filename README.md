# CPU Cooler Display para Linux

Este projeto exibe **informações do sistema** (temperatura, uso de CPU ou RAM) no display de alguns **Water Coolers** que se comunicam via **USB HID** (normalmente com software apenas para Windows).

Foi testado com o **Water Cooler Rise Mode Aura Ice Black** (ID `aa88:8666`), e pode funcionar com outros modelos que usem um protocolo HID parecido.

## ✨ Funcionalidades

- **Monitoramento em tempo real:** envia informações para o display (a cada 1 segundo).
- **Múltiplos modos de exibição:** temperatura da CPU, uso de CPU (%) ou uso de RAM (%).
- **Instalação automatizada:** scripts para instalar como **serviço do usuário** ou como **serviço do sistema**.
- **Inicialização automática:** roda via `systemd` e inicia automaticamente.
- **Detecção assistida:** os instaladores mostram `lsusb` (filtrando “Linux Foundation”) e sugerem o VID/PID (prioriza `aa88:8666`).

## 📋 Pré-requisitos (Debian/Ubuntu)

Os instaladores já conferem e instalam as dependências abaixo antes de prosseguir:

```bash
sudo apt update
sudo apt install python3-hid python3-psutil python3-pip python-is-python3
```

> Observação: se você preferir usar `pip`, ok — mas aqui padronizamos os pacotes do sistema para evitar conflitos.

## 🚀 Instalação

### 1) Identifique o seu dispositivo (VID/PID)

Conecte o cooler na USB e execute:

```bash
lsusb
```

Exemplo (modelo testado):

```text
Bus 001 Device 004: ID aa88:8666 铭研科技 温度显示HID设备
```

Neste exemplo:
- **VENDOR_ID** = `aa88`
- **PRODUCT_ID** = `8666`

### 2) Escolha o método de instalação

#### a) Instalação para Usuário (recomendado)

Instala o serviço para o seu usuário (via `systemd --user`).  
O instalador vai pedir senha de `sudo` **apenas** para criar a regra `udev` (hidraw).

```bash
chmod +x install-user.sh
./install-user.sh
```

O instalador:
- mostra `lsusb` (sem “Linux Foundation”)
- sugere VID/PID (prioriza `aa88:8666`)
- cria `/etc/udev/rules.d/99-cpu-cooler-hid.rules`
- cria o script em `~/.local/bin/cpu_cooler.py`
- cria o serviço em `~/.config/systemd/user/cpu-cooler.service`
- habilita e inicia o serviço

**Para iniciar mesmo sem login (opcional):**
```bash
sudo loginctl enable-linger $USER
```

#### b) Instalação para o Sistema (system-wide)

Instala o serviço para todos os usuários do sistema:

```bash
chmod +x install-system.sh
sudo ./install-system.sh
```

O instalador:
- mostra `lsusb` (sem “Linux Foundation”)
- sugere VID/PID (prioriza `aa88:8666`)
- cria `/etc/udev/rules.d/99-cpu-cooler-hid.rules`
- cria o script em `/usr/local/bin/cpu-cooler.py`
- cria o serviço em `/etc/systemd/system/cpu-cooler.service`
- habilita e inicia o serviço

## ✅ Uso e Verificação

### Instalação de usuário

Status:
```bash
systemctl --user status cpu-cooler.service
```

Logs em tempo real:
```bash
journalctl --user -u cpu-cooler.service -f
```

### Instalação de sistema

Status:
```bash
systemctl status cpu-cooler.service
```

Logs em tempo real:
```bash
journalctl -u cpu-cooler.service -f
```

## 🔧 Configuração Avançada

### Modos de exibição disponíveis

O script suporta diferentes **modos de exibição**, definidos por parâmetro:

| Modo | Descrição |
|-----|----------|
| `temp` | Temperatura da CPU (padrão) |
| `cpu`  | Uso da CPU em porcentagem |
| `ram`  | Uso da memória RAM em porcentagem |

#### Exemplo de execução manual

```bash
python3 cpu_cooler.py --mode temp
python3 cpu_cooler.py --mode cpu
python3 cpu_cooler.py --mode ram
```

#### Exemplo configurando no systemd

Edite o serviço e altere o `ExecStart`:

```ini
ExecStart=/usr/bin/python3 /usr/local/bin/cpu-cooler.py --mode cpu
```

Depois recarregue:

```bash
systemctl daemon-reload
systemctl restart cpu-cooler.service
```

### Fonte da temperatura da CPU

O script tenta usar `k10temp` (comum em AMD).  
Se não existir, ele usa o primeiro sensor disponível.

Para listar os sensores disponíveis:

```bash
python3 -c "import psutil; print(psutil.sensors_temperatures())"
```

### Protocolo do display (payload HID)

O envio usa um payload HID de **64 bytes**.  
Atualmente são utilizados:

```text
payload[0] = 0x00   # comando / report id
payload[1] = valor  # valor a ser exibido (0..255)
```

### Exemplos de personalização

#### Enviar uso de CPU (%)

```python
valor = int(psutil.cpu_percent(interval=0.2))
payload[1] = valor & 0xFF
```

#### Enviar uso de RAM (%)

```python
valor = int(psutil.virtual_memory().percent)
payload[1] = valor & 0xFF
```

#### Ajustar temperatura com offset

```python
temp = int(get_cpu_temp())
temp_corrigida = temp - 3
payload[1] = max(0, min(255, temp_corrigida))
```

> Observação: se o display aceitar mais de um byte, é possível usar `payload[2]` para valores maiores.

## 🗑️ Desinstalação

### a) Remover instalação de usuário

```bash
systemctl --user stop cpu-cooler.service
systemctl --user disable cpu-cooler.service
rm -f ~/.local/bin/cpu_cooler.py
rm -f ~/.config/systemd/user/cpu-cooler.service
systemctl --user daemon-reload
sudo rm -f /etc/udev/rules.d/99-cpu-cooler-hid.rules
sudo udevadm control --reload-rules && sudo udevadm trigger
```

### b) Remover instalação de sistema

```bash
sudo systemctl stop cpu-cooler.service
sudo systemctl disable cpu-cooler.service
sudo rm -f /usr/local/bin/cpu-cooler.py
sudo rm -f /etc/systemd/system/cpu-cooler.service
sudo systemctl daemon-reload
sudo rm -f /etc/udev/rules.d/99-cpu-cooler-hid.rules
sudo udevadm control --reload-rules && sudo udevadm trigger
```

## 🤔 Solução de Problemas

- **Dispositivo não encontrado:** confirme VID/PID com `lsusb` e reconecte o USB após criar a regra `udev`.
- **Permissão negada:** confirme a regra `hidraw`:
  ```bash
  cat /etc/udev/rules.d/99-cpu-cooler-hid.rules
  ```
- **Serviço não inicia:** consulte os logs na seção “Uso e Verificação”.
