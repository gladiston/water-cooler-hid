# CPU Cooler Display para Linux

Este projeto oferece uma solução para exibir **informações do sistema** em displays de Water Coolers no Linux, especialmente para dispositivos que possuem apenas software de controle para Windows.

O script envia valores (temperatura, uso de CPU ou RAM) para o display via **USB HID**.  
Foi testado com o **Water Cooler Rise Mode Aura Ice Black** (`aa88:8666`), mas pode funcionar com outros modelos que utilizem comunicação HID semelhante.

---

## ✨ Funcionalidades

- **Monitoramento em tempo real:** envio contínuo de dados ao display.
- **Múltiplos modos de exibição:** temperatura da CPU, uso da CPU (%) ou uso da RAM (%).
- **Instalação automatizada:** scripts para usuário ou sistema.
- **Inicialização automática:** integração com `systemd`.
- **Compatível com Linux:** não depende de software proprietário.

---

## ⚠️ Limitação Importante do Display (Leia antes)

Alguns modelos de water cooler — incluindo o **Rise Mode Aura Ice Black** — possuem um **layout fixo gravado no firmware do display**.

Isso significa que:

- O script **envia apenas um valor numérico** (ex.: `37`)
- O **texto exibido no display (“Temp/C”) não é controlado pelo script**
- A **linha inferior é fixa** e definida pelo próprio hardware

### O que isso implica na prática?

Mesmo ao usar os modos:

- `cpu` → uso da CPU (%)
- `ram` → uso da memória (%)

o display continuará mostrando algo como:

```
37
Temp/C
```

Isso **não é um erro do script**.

👉 O display **sempre assume que o número recebido é temperatura em °C**, pois este é o único modo oficialmente suportado pelo firmware.

### Por que isso acontece?

O protocolo HID utilizado:
- **não aceita texto**
- **não permite alterar unidades**
- **não permite mudar o layout**
- trabalha apenas com **bytes numéricos (0–255)**

Todo o desenho do display (texto, unidade, posição) é feito internamente pelo dispositivo.

### Conclusão

> Ao usar os modos `cpu` ou `ram`, o valor exibido continua correto,  
> **mas o texto “Temp/C” não corresponde mais ao significado real do número.**

Essa limitação foi documentada aqui para evitar confusão ou falsas expectativas.

---

## 📋 Pré-requisitos

Distribuições Debian/Ubuntu:

```bash
sudo apt update
sudo apt install python3-hid python3-psutil python3-pip python-is-python3
```

---

## 🚀 Instalação

Recomenda-se utilizar os scripts automatizados.

### Identificar o dispositivo USB

```bash
lsusb
```

Exemplo do modelo testado:

```text
Bus 001 Device 004: ID aa88:8666 铭研科技 温度显示HID设备
```

- **VENDOR_ID:** `aa88`
- **PRODUCT_ID:** `8666`

Os scripts de instalação fazem essa detecção automaticamente.

---

## ⚙️ Modos de Exibição

O script suporta três modos:

| Modo | Informação enviada |
|-----|-------------------|
| `temp` | Temperatura da CPU (°C) |
| `cpu`  | Uso da CPU (%) |
| `ram`  | Uso da RAM (%) |

> ⚠️ Independentemente do modo, o texto do display continuará mostrando “Temp/C”.

### Exemplo de execução manual

```bash
python3 cpu_cooler.py --mode temp
python3 cpu_cooler.py --mode cpu
python3 cpu_cooler.py --mode ram
```

---

## 🔧 Personalização (Avançado)

Exemplo de envio de uso de CPU:

```python
valor = int(psutil.cpu_percent(interval=0.2))
payload[1] = valor & 0xFF
```

Exemplo de envio de uso de RAM:

```python
valor = int(psutil.virtual_memory().percent)
payload[1] = valor & 0xFF
```

---

## 🗑️ Desinstalação

Os procedimentos de remoção permanecem os mesmos descritos nos scripts de instalação.

---

## 🤔 Solução de Problemas

- **Texto incorreto no display:** comportamento esperado; ver seção “Limitação Importante do Display”.
- **Dispositivo não encontrado:** verifique VID/PID e a regra `udev`.
- **Permissão negada:** confirme `/etc/udev/rules.d/99-cpu-cooler-hid.rules`.
