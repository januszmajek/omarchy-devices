#!/usr/bin/env python3
"""Long-running backend for the Devices plugin.

Talks to Logitech receivers through Solaar's library and to USB headsets
through headsetcontrol. Prints one JSON state object per line on stdout and
reads one JSON command per line on stdin:

  {"cmd": "refresh"}
  {"cmd": "set", "serial": "92D3C1E9", "setting": "dpi", "value": "1600"}
  {"cmd": "headset", "id": "0x046d:0x0aba", "key": "sidetone", "value": 32}

Settings written here are remembered in $XDG_STATE_HOME/omarchy-devices and
written again when a device wakes up or reconnects, because many Logitech
devices forget them when they power off.
"""

import json
import os
import select
import shutil
import subprocess
import sys
import time

POLL_SECONDS = 30
STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "omarchy-devices")
SAVED_FILE = os.path.join(STATE_DIR, "settings.json")

# Kinds from logitech_receiver.settings.Kind that the panel can render.
TOGGLE, CHOICE, RANGE = 1, 2, 4

# Settings that are unsafe without the Solaar daemon (diversion hands buttons
# and wheels to Solaar's rule engine) or that move the device away from this
# computer.
HIDDEN_SETTINGS = {"change-host", "hires-scroll-mode", "thumb-scroll-mode", "divert-keys", "divert-gkeys"}

HEADSET_INACTIVE_CHOICES = [0, 5, 10, 15, 30, 60, 90]


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def log(message):
    sys.stderr.write(f"devices-helper: {message}\n")
    sys.stderr.flush()


def load_saved():
    try:
        with open(SAVED_FILE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def store_saved(saved):
    os.makedirs(STATE_DIR, exist_ok=True)
    tmp = SAVED_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(saved, f, indent=1)
    os.replace(tmp, SAVED_FILE)


class Logitech:
    def __init__(self, saved):
        self.saved = saved
        self.available = False
        self.error = ""
        self.devices = {}  # serial -> device object
        self.receivers = []
        self.cache = {}  # serial -> last emitted entry
        try:
            from logitech_receiver import base, receiver, settings  # noqa: F401
            self.base, self.receiver_mod = base, receiver
            self.available = True
        except Exception as e:  # Solaar not installed
            self.error = f"Solaar is not installed ({e})"

    def enumerate(self):
        if not self.available:
            return
        self.receivers = []
        self.devices = {}
        for info in self.base.receivers():
            try:
                r = self.receiver_mod.create_receiver(self.base, info)
            except Exception as e:
                log(f"cannot open receiver {info.path}: {e}")
                self.error = "Cannot open the Logitech receiver (permission?)"
                continue
            if not r:
                continue
            self.receivers.append(r)
            for d in r:
                if d and d.serial:
                    self.devices[d.serial] = d

    def setting_entry(self, s):
        kind = int(s.kind)
        if s.name in HIDDEN_SETTINGS or kind not in (TOGGLE, CHOICE, RANGE):
            return None
        try:
            value = s.read(cached=False)
        except Exception:
            value = None
        if value is None:
            return None
        entry = {"name": s.name, "label": s.label, "description": (s.description or "").replace("\n", " ")}
        validator = s._validator
        if kind == TOGGLE:
            entry.update(type="toggle", value=bool(value))
        elif kind == RANGE or getattr(validator, "min_value", None) is not None:
            entry.update(type="range", value=int(value), min=int(validator.min_value), max=int(validator.max_value))
        else:
            choices = [str(c) for c in (s.choices or [])]
            current = next((str(c) for c in (s.choices or []) if int(c) == int(value)), str(value))
            entry.update(type="choice", value=current, choices=choices)
        return entry

    def device_entry(self, d, receiver_name, with_settings):
        entry = {
            "id": d.serial,
            "source": "logitech",
            "name": d.name or d.codename or "Logitech device",
            "kind": str(d.kind),
            "connection": receiver_name,
            "online": bool(d.online),
            "battery": None,
            "charging": False,
            "settings": [],
        }
        if not d.online:
            return entry
        try:
            b = d.battery()
        except Exception:
            b = None
        if b is not None and b.level is not None:
            entry["battery"] = int(b.level)
            entry["charging"] = "CHARG" in str(b.status).upper() and "DIS" not in str(b.status).upper()
        if with_settings:
            for s in d.settings or []:
                se = self.setting_entry(s)
                if se:
                    entry["settings"].append(se)
        else:
            entry["settings"] = self.cache.get(d.serial, {}).get("settings", [])
        return entry

    def reapply(self, d):
        for name, value in self.saved.get(d.serial, {}).items():
            try:
                self.write(d, name, value)
            except Exception as e:
                log(f"reapply {d.name} {name}: {e}")

    def write(self, d, name, value):
        s = next((s for s in d.settings or [] if s.name == name), None)
        if s is None:
            raise ValueError(f"{d.name} has no setting {name}")
        kind = int(s.kind)
        if kind == TOGGLE:
            v = value if isinstance(value, bool) else str(value).lower() in ("1", "true", "on", "yes")
        elif kind == CHOICE and getattr(s._validator, "min_value", None) is None:
            v = next((c for c in s.choices if str(c) == str(value)), None)
            if v is None:
                raise ValueError(f"{value} is not a valid choice for {name}")
        else:
            v = int(value)
        if s.write(v) is None:
            raise RuntimeError(f"{d.name} did not accept {name}")

    def poll(self, full):
        if not self.available:
            return []
        if full or not self.receivers:
            self.enumerate()
        out = []
        for r in self.receivers:
            for d in list(r):
                if not d or not d.serial:
                    continue
                self.devices[d.serial] = d
                was_online = self.cache.get(d.serial, {}).get("online", False)
                try:
                    d.ping()
                except Exception:
                    pass
                woke = d.online and not was_online
                if woke:
                    self.reapply(d)
                entry = self.device_entry(d, r.name, with_settings=full or woke)
                self.cache[d.serial] = entry
                out.append(entry)
        return out

    def set(self, serial, name, value):
        d = self.devices.get(serial)
        if d is None:
            raise ValueError("Unknown device")
        self.write(d, name, value)
        self.saved.setdefault(serial, {})[name] = value
        store_saved(self.saved)
        entry = self.device_entry(d, self.cache.get(serial, {}).get("connection", ""), with_settings=True)
        self.cache[serial] = entry


class Headsets:
    def __init__(self, saved):
        self.saved = saved
        self.binary = shutil.which("headsetcontrol")
        self.cache = {}

    def run(self, *args):
        return subprocess.run([self.binary, *args], capture_output=True, text=True, timeout=10)

    def poll(self):
        if not self.binary:
            return []
        try:
            data = json.loads(self.run("-o", "json").stdout or "{}")
        except Exception as e:
            log(f"headsetcontrol: {e}")
            return []
        out = []
        for h in data.get("devices", []):
            hid = f"{h.get('id_vendor')}:{h.get('id_product')}"
            caps = h.get("capabilities_str", [])
            battery = h.get("battery") or {}
            online = battery.get("status") not in ("BATTERY_UNAVAILABLE", None)
            saved = self.saved.get("headset:" + hid, {})
            was_online = self.cache.get(hid, False)
            if online and not was_online:
                for key, value in saved.items():
                    self.apply(key, value)
            self.cache[hid] = online
            settings = []
            if "sidetone" in caps:
                settings.append({"name": "sidetone", "label": "Sidetone", "type": "range", "min": 0, "max": 128,
                                 "value": int(saved.get("sidetone", 0)),
                                 "description": "How loud you hear your own microphone"})
            if "inactive time" in caps:
                settings.append({"name": "inactive", "label": "Auto power-off", "type": "choice",
                                 "choices": [str(c) for c in HEADSET_INACTIVE_CHOICES],
                                 "value": str(saved.get("inactive", 0)),
                                 "description": "Minutes of silence before the headset turns off (0 = never)"})
            level = battery.get("level", -1)
            out.append({
                "id": hid,
                "source": "headset",
                "name": h.get("product") or h.get("device") or "Headset",
                "kind": "headset",
                "connection": "USB dongle",
                "online": online,
                "battery": level if online and level >= 0 else None,
                "charging": battery.get("status") == "BATTERY_CHARGING",
                "settings": settings,
            })
        return out

    def apply(self, key, value):
        flag = {"sidetone": "-s", "inactive": "-i"}[key]
        result = self.run(flag, str(int(value)))
        if result.returncode != 0:
            raise RuntimeError((result.stderr or result.stdout).strip() or f"headsetcontrol {flag} failed")

    def set(self, hid, key, value):
        self.apply(key, value)
        self.saved.setdefault("headset:" + hid, {})[key] = int(value)
        store_saved(self.saved)


def usb_key(device_id):
    """'0x046d:0x0aba' -> '046d:0aba'."""
    return ":".join(part.lower().removeprefix("0x").zfill(4) for part in device_id.split(":"))


# Headsets whose mute button acts inside the headset without telling the
# computer: the system mute shown for them can be stale after a press.
# Checked on the PRO X Wireless by reading its USB audio mute control
# directly (it follows the button) and seeing that nothing tells the driver
# when it changes.
UNREPORTED_MIC_BUTTON = {"046d:0aba"}


def mark_mic_button(devices):
    for d in devices:
        if d["source"] == "headset" and usb_key(d["id"]) in UNREPORTED_MIC_BUTTON:
            d["micButtonUnreported"] = True
    return devices


def main():
    saved = load_saved()
    logitech = Logitech(saved)
    headsets = Headsets(saved)
    state = {"type": "state", "devices": [], "errors": []}

    def publish(full):
        devices = headsets.poll() + logitech.poll(full)
        # Solaar also sees some headsets; headsetcontrol knows them better.
        if any(d["source"] == "headset" for d in devices):
            devices = [d for d in devices if not (d["source"] == "logitech" and d["kind"] == "headset")]
        state["devices"] = mark_mic_button(devices)
        state["errors"] = [e for e in [logitech.error] if e]
        if not headsets.binary:
            state["errors"].append("headsetcontrol is not installed")
        emit(state)

    publish(full=True)
    last_poll = time.monotonic()
    while True:
        now = time.monotonic()
        timeout = max(0.0, POLL_SECONDS - (now - last_poll))
        ready, _, _ = select.select([sys.stdin], [], [], timeout)
        if ready:
            line = sys.stdin.readline()
            if not line:
                return  # the shell closed our stdin: exit with it
            try:
                cmd = json.loads(line)
                if cmd.get("cmd") == "set":
                    logitech.set(cmd["serial"], cmd["setting"], cmd["value"])
                elif cmd.get("cmd") == "headset":
                    headsets.set(cmd["id"], cmd["key"], cmd["value"])
                elif cmd.get("cmd") != "refresh":
                    raise ValueError(f"unknown command {cmd.get('cmd')}")
                publish(full=cmd.get("cmd") == "refresh")
            except Exception as e:
                emit({"type": "error", "message": str(e)})
            last_poll = time.monotonic()
        elif time.monotonic() - last_poll >= POLL_SECONDS:
            publish(full=False)
            last_poll = time.monotonic()


if __name__ == "__main__":
    main()
