.pragma library

// Nerd Font (Material Design) glyphs.
var ICONS = {
  devices: 0xF0FB0,
  batteryAlert: 0xF0083,
  mouse: 0xF037D,
  keyboard: 0xF030C,
  headset: 0xF02CE,
  headphones: 0xF02CB,
  gamepad: 0xF02B4,
  phone: 0xF011C,
  speaker: 0xF04C3,
  device: 0xF00AF,
  mic: 0xF036C,
  micOff: 0xF036D
}

function icon(kind) {
  var code = ICONS[kind] || ICONS.device
  return String.fromCodePoint(code)
}

function deviceLabel(device) {
  if (!device) return ""
  return String(device.deviceName || device.name || "").trim()
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

// Helper devices plus paired Bluetooth devices in one list: online first,
// then by name. Bluetooth objects are copied into plain values so rows never
// hold live BlueZ wrappers.
function mergeDevices(helperDevices, btDevices, micStates) {
  var list = []
  for (var i = 0; i < helperDevices.length; i++) {
    var h = Object.assign({}, helperDevices[i])
    h.mic = micStates[h.id] || null
    if (h.mic && h.micHardwareMuted !== undefined) {
      h.mic = Object.assign({}, h.mic, { hardwareMuted: h.micHardwareMuted, estimated: !!h.micEstimated })
    }
    list.push(h)
  }
  for (var j = 0; j < btDevices.length; j++) {
    var b = btDevices[j]
    if (!b || !(b.paired || b.bonded || b.trusted)) continue
    list.push({
      id: b.address,
      source: "bluetooth",
      name: deviceLabel(b) || b.address,
      kind: bluetoothKind(b),
      connection: "Bluetooth",
      online: !!b.connected,
      battery: b.connected && b.batteryAvailable ? Math.round(b.battery * 100) : null,
      charging: false,
      settings: [],
      mic: null
    })
  }
  list.sort(function(a, b) {
    return (b.online - a.online) || a.name.localeCompare(b.name)
  })
  return list
}

// Every battery reading, devices on the charger last and the rest lowest
// first, as { id, name, kind, connection, level, charging }.
function batteries(devices) {
  var list = []
  for (var i = 0; i < devices.length; i++) {
    var d = devices[i]
    if (d.online && d.battery !== null && d.battery !== undefined)
      list.push({ id: d.id, name: d.name, kind: d.kind, connection: d.connection, level: d.battery, charging: d.charging })
  }
  list.sort(function(a, b) { return (a.charging - b.charging) || (a.level - b.level) })
  return list
}

// The PipeWire capture node belonging to a USB headset, matched by name.
function sourceNodeFor(headset, nodes) {
  var want = String(headset.name || "").toLowerCase()
  if (!want) return null
  for (var i = 0; i < nodes.length; i++) {
    var n = nodes[i]
    if (!n || n.isSink || n.isStream || !n.audio) continue
    var text = (String(n.description || "") + " " + String(n.nickname || "") + " " + String(n.name || "")).toLowerCase()
    if (text.indexOf(want) >= 0) return n
  }
  return null
}

function status(dev) {
  if (!dev.online) return "Not connected"
  var parts = []
  if (dev.battery !== null && dev.battery !== undefined) parts.push(Math.round(dev.battery) + "%")
  if (dev.charging) parts.push("charging")
  return parts.length ? parts.join(" · ") : "Connected"
}

// Muted by the headset button, in the system, both, or live. Many headsets
// (the Logitech PRO X Wireless among them) mute inside the headset without
// telling the computer; then hardwareMuted is undefined and only the system
// state is claimed.
function micText(mic) {
  if (!mic) return ""
  var sys = mic.systemMuted === true
  if (mic.hardwareMuted === undefined || mic.hardwareMuted === null)
    return sys ? "Mic muted (system)" : "Mic on (system)"
  var hw = mic.hardwareMuted === true
  var est = mic.estimated ? " (est.)" : ""
  if (hw && sys) return "Mic muted · headset button" + est + " + system"
  if (hw) return "Mic muted · headset button" + est
  if (sys) return "Mic muted · system"
  return "Mic live" + est
}

function micMuted(mic) {
  return !!mic && (mic.hardwareMuted === true || mic.systemMuted === true)
}

// One line: the bar's tooltip window does not grow for multi-line text.
function tooltip(lowDevices, batteries) {
  if (lowDevices.length)
    return "Low battery: " + lowDevices.map(function(d) { return d.name + " " + d.level + "%" }).join(", ")
  if (batteries.length)
    return "Devices · lowest: " + batteries[0].name + " " + batteries[0].level + "%"
  return "Devices"
}
