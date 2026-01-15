#!/usr/bin/env python3
# cpu_cooler.py
#
# Exibe informações do sistema (temperatura, uso de CPU ou RAM)
# no display de um Water Cooler via USB HID.
#
# Modos disponíveis:
#   --mode temp   (temperatura da CPU, padrão)
#   --mode cpu    (uso de CPU em %)
#   --mode ram    (uso de RAM em %)
#
# Exemplo:
#   python3 cpu_cooler.py --mode cpu
#
# Dependências (Debian/Ubuntu):
#   python3-hid python3-psutil

import hid
import psutil
import argparse
from threading import Event, Thread

VENDOR_ID = 0xaa88
PRODUCT_ID = 0x8666


def get_cpu_temp() -> int:
    temps = psutil.sensors_temperatures()

    if "k10temp" in temps and temps["k10temp"]:
        return int(temps["k10temp"][0].current)

    for sensor_list in temps.values():
        if sensor_list:
            return int(sensor_list[0].current)

    raise RuntimeError("Nenhum sensor de temperatura encontrado")


def get_cpu_percent() -> int:
    return int(psutil.cpu_percent(interval=0.2))


def get_ram_percent() -> int:
    return int(psutil.virtual_memory().percent)


def open_device(vid: int, pid: int) -> hid.Device:
    for d in hid.enumerate(vid, pid):
        return hid.Device(path=d["path"])
    raise FileNotFoundError("Dispositivo HID não encontrado")


def build_payload(value: int) -> bytes:
    payload = bytearray(64)
    payload[0] = 0x00          # report / comando
    payload[1] = value & 0xFF  # valor (0..255)
    return bytes(payload)


def send_value(dev: hid.Device, mode: str) -> None:
    try:
        if mode == "cpu":
            value = get_cpu_percent()
        elif mode == "ram":
            value = get_ram_percent()
        else:
            value = get_cpu_temp()

        payload = build_payload(value)
        dev.write(payload)

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
    parser = argparse.ArgumentParser(
        description="Envia informações do sistema para display de Water Cooler via USB HID"
    )
    parser.add_argument(
        "--mode",
        choices=["temp", "cpu", "ram"],
        default="temp",
        help="Informação a ser exibida no display"
    )
    args = parser.parse_args()

    try:
        dev = open_device(VENDOR_ID, PRODUCT_ID)
        print(f"✅ HID conectado | modo: {args.mode}")
    except Exception as e:
        print(f"❌ Erro ao abrir dispositivo HID: {e}")
        return 1

    cancel = call_repeatedly(1, send_value, dev, args.mode)

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
