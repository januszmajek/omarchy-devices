import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import "Model.js" as Model

// Owns the single devices-helper.py process and everything that must happen
// once rather than once per monitor: the merged device list, low-battery
// notifications and the headset microphone state. Bar widgets only read
// from here.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null

  // Set by the bar widget from its shell.json entry.
  property int lowBattery: 20

  // Helper-backed devices (Logitech receivers, USB headsets): see the state
  // shape at the top of scripts/devices-helper.py.
  property var helperDevices: []
  property var errors: []
  property string lastError: ""
  property bool ready: false

  // Settings sent but not yet confirmed by a fresh state line, keyed
  // "<device id>/<setting>", so the panel can show the new value at once.
  property var pending: ({})

  readonly property var btDevices: Bluetooth.devices ? Bluetooth.devices.values : []
  readonly property var pwNodes: Pipewire.nodes ? Pipewire.nodes.values : []

  // Every device, however it connects, as plain objects:
  // { id, source, name, kind, connection, online, battery, charging, settings, mic }
  readonly property var devices: Model.mergeDevices(helperDevices, btDevices, micStates)
  readonly property var batteries: Model.batteries(devices)
  readonly property var lowDevices: batteries.filter(b => !b.charging && b.level <= lowBattery)

  // ---------- Headset microphone ----------

  // The PipeWire capture node of each online helper headset, so its system
  // mute can be shown next to the headset's own mute button.
  readonly property var headsetSources: {
    var map = {}
    for (var i = 0; i < helperDevices.length; i++) {
      var h = helperDevices[i]
      if (h.kind !== "headset") continue
      var node = Model.sourceNodeFor(h, pwNodes)
      if (node) map[h.id] = node
    }
    return map
  }

  PwObjectTracker {
    objects: Object.keys(root.headsetSources).map(k => root.headsetSources[k])
  }

  readonly property var micStates: {
    var map = {}
    for (var id in headsetSources) {
      var node = headsetSources[id]
      map[id] = { systemMuted: !!(node.audio && node.audio.muted), nodeId: node.id }
    }
    return map
  }

  function toggleSystemMic(device) {
    var node = headsetSources[device.id]
    if (node && node.audio) node.audio.muted = !node.audio.muted
  }

  // ---------- Low-battery notifications ----------

  // Device ids already warned about; cleared once the device charges or
  // climbs back above the threshold, so each drop warns exactly once.
  property var warned: ({})

  onLowDevicesChanged: {
    var next = {}
    for (var i = 0; i < lowDevices.length; i++) {
      var d = lowDevices[i]
      next[d.id] = true
      if (!warned[d.id]) {
        Quickshell.execDetached([
          "notify-send", "-u", "critical", "-a", "Devices", "-i", "battery-caution",
          "Low battery: " + d.name,
          d.name + " (" + d.connection + ") is at " + d.level + "%."
        ])
      }
    }
    warned = next
  }

  // ---------- Helper process ----------

  readonly property string helperPath: {
    var url = Qt.resolvedUrl("scripts/devices-helper.py").toString()
    return url.indexOf("file://") === 0 ? decodeURIComponent(url.slice(7)) : url
  }

  function send(command) {
    if (!helper.running) return
    helper.write(JSON.stringify(command) + "\n")
  }

  function refresh() { send({ cmd: "refresh" }) }

  function setValue(device, setting, value) {
    if (!device) return
    var next = Object.assign({}, pending)
    next[device.id + "/" + setting] = value
    pending = next
    if (device.source === "headset") send({ cmd: "headset", id: device.id, key: setting, value: value })
    else send({ cmd: "set", serial: device.id, setting: setting, value: value })
  }

  function valueFor(device, setting) {
    var key = device.id + "/" + setting.name
    return key in pending ? pending[key] : setting.value
  }

  function handleLine(line) {
    var message
    try { message = JSON.parse(line) } catch (e) { return }
    if (message.type === "state") {
      helperDevices = message.devices || []
      errors = message.errors || []
      pending = ({})
      ready = true
    } else if (message.type === "error") {
      lastError = message.message || "Unknown error"
      pending = ({})
      errorClear.restart()
    }
  }

  Process {
    id: helper
    command: ["python3", "-I", root.helperPath]
    running: true
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root.handleLine(line) } }
    stderr: SplitParser {
      onRead: function(line) {
        if (line.indexOf("rules cannot access") < 0) console.warn("devices-helper:", line)
      }
    }
    onExited: function(code) {
      root.ready = false
      restart.restart()
    }
  }

  // A crashed helper comes back after a pause instead of in a tight loop.
  Timer {
    id: restart
    interval: 5000
    onTriggered: helper.running = true
  }

  Timer {
    id: errorClear
    interval: 6000
    onTriggered: root.lastError = ""
  }
}
