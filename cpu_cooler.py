#!/usr/bin/env python3
# cpu_cooler.py
#
# Envia um valor numérico para o display do water cooler via USB HID.
#
# Correções/ajustes desta versão:
# - Compatível com diferentes bindings do "hid":
#     * alguns expõem hid.Device(...)
#     * outros expõem hid.device() (minúsculo) + open_path(...)
# - Não encerra o processo quando o dispositivo ainda não está pronto:
#   tenta reconectar em loop (útil para systemd).
# - Suporta modos: temp (padrão), cpu, ram.
# - Payload sempre em bytes/bytearray (nunca list[int]).
#
# Observação importante:
# - O texto exibido na linha inferior do display (ex: "Temp/C") é FIXO do hardware
#   e não pode ser alterado por este script. O script envia apenas o número.

import argparse
import sys
import time

import hid
import psutil


# ---------------------------- leituras ----------------------------

def get_cpu_temp() -> int:
    temps = psutil.sensors_temperatures() or {}
    # tenta nomes comuns
    for key in ("k10temp", "coretemp"):
        if key in temps and temps[key]:
            return int(temps[key][0].current)
    # fallback: primeiro sensor encontrado
    for sensor_list in temps.values():
        if sensor_list:
            return int(sensor_list[0].current)
    raise RuntimeError("Nenhum sensor de temperatura encontrado (psutil.sensors_temperatures())")


def get_cpu_percent() -> int:
    # interval curto para ter leitura real e estável
    return int(psutil.cpu_percent(interval=0.2))


def get_ram_percent() -> int:
    return int(psutil.virtual_memory().percent)


# ---------------------------- HID helpers ----------------------------

def build_payload(value: int) -> bytes:
    # Payload padrão (64 bytes). Muitos desses displays usam 64 bytes.
    payload = bytearray(64)
    payload[0] = 0x00          # Report ID / comando (pode variar por modelo)
    payload[1] = value & 0xFF  # valor (0..255)
    return bytes(payload)


def open_device_by_vidpid(vid: int, pid: int):
    devs = hid.enumerate(vid, pid) or []
    if not devs:
        raise FileNotFoundError(f"Nenhum dispositivo HID encontrado para VID:PID {vid:04x}:{pid:04x}")

    path = devs[0].get("path")
    if not path:
        raise RuntimeError("Dispositivo encontrado, mas sem 'path' em hid.enumerate()")

    # API 1) hid.Device(...)
    if hasattr(hid, "Device"):
        return hid.Device(path=path)

    # API 2) hid.device() + open_path(...)
    if hasattr(hid, "device"):
        d = hid.device()
        d.open_path(path)
        return d

    raise AttributeError("O módulo 'hid' não expõe 'Device' nem 'device()'.")


def log(msg: str):
    print(msg, file=sys.stderr, flush=True)


# ---------------------------- main loop ----------------------------

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--vid", default="aa88", help="VENDOR_ID em hex (sem 0x). Ex: aa88")
    parser.add_argument("--pid", default="8666", help="PRODUCT_ID em hex (sem 0x). Ex: 8666")
    parser.add_argument("--mode", default="temp", choices=["temp", "cpu", "ram"],
                        help="Modo de exibição: temp (padrão), cpu, ram")
    parser.add_argument("--interval", type=float, default=1.0,
                        help="Intervalo de atualização em segundos (padrão: 1.0)")
    args = parser.parse_args()

    try:
        vid = int(args.vid, 16)
        pid = int(args.pid, 16)
    except ValueError:
        raise SystemExit("VID/PID inválidos. Use hex sem 0x. Ex: --vid aa88 --pid 8666")

    dev = None

    while True:
        try:
            if dev is None:
                dev = open_device_by_vidpid(vid, pid)
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
            # Em ambiente systemd, cair fora aqui derruba o serviço.
            # Então fechamos e tentamos novamente.
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
