#!/usr/bin/env python3
# cpu_cooler.py
#
# Envia a temperatura atual da CPU para o display de um water cooler via USB HID
#
# Correção desta versão:
# - hid.Device.write() (hidapi Python) espera bytes/bytearray, não list[int].
#
# Requisitos:
#   pip install hidapi psutil

import hid
import psutil
from threading import Event, Thread

# -----------------------------------------------------------------------------
# Leitura da temperatura da CPU
# -----------------------------------------------------------------------------
def get_cpu_temp():
    temps = psutil.sensors_temperatures()

    if 'k10temp' in temps and temps['k10temp']:
        return temps['k10temp'][0].current

    for sensor_list in temps.values():
        if sensor_list:
            return sensor_list[0].current

    raise RuntimeError('Nenhum sensor de temperatura encontrado')

# -----------------------------------------------------------------------------
# IDs do dispositivo HID
# -----------------------------------------------------------------------------
VENDOR_ID  = 0xaa88
PRODUCT_ID = 0x8666

# -----------------------------------------------------------------------------
# Abre o device via path (mais robusto no Linux)
# -----------------------------------------------------------------------------
device = None
for d in hid.enumerate(VENDOR_ID, PRODUCT_ID):
    device = hid.Device(path=d['path'])
    break

if device is None:
    print('❌ Dispositivo HID não encontrado')
    raise SystemExit(1)

print('✅ HID conectado via path')

# -----------------------------------------------------------------------------
# Envio da temperatura ao display
# -----------------------------------------------------------------------------
def write_to_cpu_fan_display(dev):
    try:
        cpu_temp = int(get_cpu_temp()) & 0xFF

        # Payload HID padrão (64 bytes)
        payload = bytearray(64)
        payload[0] = 0x00          # Report ID / comando (pode variar por modelo)
        payload[1] = cpu_temp      # Temperatura em °C

        dev.write(bytes(payload))  # <-- importante: bytes/bytearray, não list
        print(f'📤 Temperatura enviada: {cpu_temp}°C')
    except Exception as e:
        print(f'⚠️ Erro ao enviar dados: {e}')

# -----------------------------------------------------------------------------
# Execução periódica
# -----------------------------------------------------------------------------
def call_repeatedly(interval, func, *args):
    stopped = Event()

    def loop():
        while not stopped.wait(interval):
            func(*args)

    Thread(target=loop, daemon=True).start()
    return stopped.set

# -----------------------------------------------------------------------------
# Configuração
# -----------------------------------------------------------------------------
INTERVAL_SECONDS = 1

cancel_future_calls = call_repeatedly(
    INTERVAL_SECONDS,
    write_to_cpu_fan_display,
    device
)

# -----------------------------------------------------------------------------
# Loop principal
# -----------------------------------------------------------------------------
try:
    while True:
        Event().wait(10)
except KeyboardInterrupt:
    print('\n⏹️ Encerrando...')
    cancel_future_calls()
    device.close()
