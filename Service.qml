import QtQuick
import Quickshell
import Quickshell.Io

// Owns the single devices-helper.py process. Bar widgets exist once per
// monitor, so they all read state from here instead of each starting a
// helper that would fight over the same receiver.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null

  // Helper-backed devices (Logitech receivers, USB headsets): see the state
  // shape at the top of scripts/devices-helper.py.
  property var devices: []
  property var errors: []
  property string lastError: ""
  property bool ready: false

  // Settings sent but not yet confirmed by a fresh state line, keyed
  // "<device id>/<setting>", so the panel can show the new value at once.
  property var pending: ({})

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
      devices = message.devices || []
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
