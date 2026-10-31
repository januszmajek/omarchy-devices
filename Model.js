.pragma library

// Nerd Font (Material Design) glyphs per device kind.
var ICONS = {
  mouse: 0xF037D,
  keyboard: 0xF030C,
  headset: 0xF02CE,
  headphones: 0xF02CB,
  gamepad: 0xF02B4,
  phone: 0xF011C,
  speaker: 0xF04C3,
  device: 0xF00AF
}

function icon(kind) {
  var code = ICONS[kind] || ICONS.device
  return String.fromCodePoint(code)
}

function deviceLabel(device) {
  if (!device) return ""
  return String(device.deviceName || device.name || "").trim()
}

function hasHumanName(device) {
  var label = deviceLabel(device)
  return label !== ""
    && !/^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(label)
    && !/^[0-9a-f]{8}-[0-9a-f]{4}-/i.test(label)
}

// BlueZ reports a freedesktop icon name (input-gaming, audio-headphones, ...);
// fall back to the name for devices that leave it empty.
function bluetoothKind(device) {
  var hint = String((device && device.icon) || "") + " " + deviceLabel(device)
  hint = hint.toLowerCase()
  if (/gaming|controller|gamepad|joystick|xbox|dualsense|dualshock/.test(hint)) return "gamepad"
  if (/keyboard|keychron|keys/.test(hint)) return "keyboard"
  if (/mouse|pointer|mx master|trackball/.test(hint)) return "mouse"
  if (/headset/.test(hint)) return "headset"
  if (/headphone|airpods|buds|earbud|audio-card/.test(hint)) return "headphones"
  if (/speaker/.test(hint)) return "speaker"
  if (/phone/.test(hint)) return "phone"
  return "device"
}

function percent(level) {
  return Math.round(level) + "%"
}

function helperStatus(dev) {
  if (!dev.online) return dev.connection + " · offline"
  var parts = [dev.connection]
  if (dev.battery !== null && dev.battery !== undefined) parts.push(percent(dev.battery))
  if (dev.charging) parts.push("charging")
  return parts.join(" · ")
}

function bluetoothStatus(dev, pending) {
  if (pending === "connect" || pending === "pair" || dev.pairing) return "Connecting…"
  if (pending === "disconnect") return "Disconnecting…"
  if (pending === "forget") return "Forgetting…"
  if (!dev.connected) return dev.paired || dev.bonded || dev.trusted ? "Not connected" : ""
  var parts = ["Connected"]
  if (dev.batteryAvailable) parts.push(percent(dev.battery * 100))
  return parts.join(" · ")
}

// Every battery reading we have, lowest first, as { name, kind, level, charging }.
function batteries(helperDevices, btDevices) {
  var list = []
  for (var i = 0; i < helperDevices.length; i++) {
    var h = helperDevices[i]
    if (h.online && h.battery !== null && h.battery !== undefined)
      list.push({ name: h.name, kind: h.kind, level: h.battery, charging: h.charging })
  }
  for (var j = 0; j < btDevices.length; j++) {
    var b = btDevices[j]
    if (b && b.connected && b.batteryAvailable)
      list.push({ name: deviceLabel(b), kind: bluetoothKind(b), level: Math.round(b.battery * 100), charging: false })
  }
  // Devices on the charger go last: the bar should warn about the one that
  // is actually running down.
  list.sort(function(a, b) { return (a.charging - b.charging) || (a.level - b.level) })
  return list
}
