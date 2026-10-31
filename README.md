# Devices — an Omarchy bar plugin

Battery levels and settings for every wireless device on your desk, in one
panel, however it is connected:

- **Logitech Bolt / Unifying receivers** — battery, plus DPI, SmartShift,
  ratchet/free-spin, scroll direction, high-resolution scrolling, keyboard
  backlight, Fn-key swap and OS layout (whatever the device supports)
- **USB headset dongles** (Logitech G PRO X and anything else
  [HeadsetControl](https://github.com/Sapd/HeadsetControl) supports) — battery,
  sidetone, auto power-off
- **Bluetooth** — controllers, earbuds, keyboards: connect, disconnect, forget,
  scan and pair, battery when the device reports it, and the Bluetooth power
  switch

The bar shows the device with the lowest battery (devices on the charger are
ranked last) and turns the urgent colour below the warning level.

![Devices panel](preview.png)

## Requirements

- Omarchy with the plugin-capable shell (`omarchy-shell`)
- `solaar` — Logitech receivers. Only its Python library and udev rules are
  used; the Solaar app does not need to run.
- `headsetcontrol` — USB headsets

```bash
sudo pacman -S solaar headsetcontrol
```

Unplug and replug the receiver and headset dongle once afterwards so their
udev permission rules apply.

## Install

```bash
omarchy plugin add https://github.com/januszmajek/omarchy-devices --enable
```

Move it on the bar with `omarchy bar move januszmajek.devices --section right`.

## Use

- **Click** the bar icon to open the panel, **right-click** to refresh.
- **Click a receiver or dongle device** to show its settings. Changes apply
  immediately.
- **Click a Bluetooth device** to connect or disconnect it; hover for the
  forget button. The magnifier scans for new devices; click one to pair.

Settings you change are saved to
`~/.local/state/omarchy-devices/settings.json` and written again whenever the
device wakes up or reconnects, because many Logitech devices and headsets
forget them when they power off.

Not shown on purpose: button diversion and wheel diversion (they hand the
buttons to Solaar's rule engine, so without the Solaar app running they stop
working) and host switching (one click would send the device to another
computer). Use the Solaar app for those.

## Settings

Inline on the widget's entry in `~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
| --- | --- | --- |
| `lowBattery` | `20` | At or below this percentage the bar turns the urgent colour |
| `showPercent` | `true` | Show the lowest battery percentage next to the icon |

## How it works

`Service.qml` runs one long-lived `scripts/devices-helper.py` for all
monitors. The helper uses Solaar's `logitech_receiver` library and
`headsetcontrol`, prints a JSON state line on every change or every 30
seconds, and takes JSON commands on stdin. `Panel.qml` is the bar widget and
popup; Bluetooth comes straight from Quickshell's BlueZ bindings and Omarchy's
`omarchy-bluetooth-device` / `omarchy-bluetooth-power` helpers.

Run the helper on its own to see what it sees:

```bash
python3 scripts/devices-helper.py   # type {"cmd":"refresh"} and Enter; Ctrl-D quits
```

## License

MIT
