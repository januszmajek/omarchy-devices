import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Bluetooth
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "januszmajek.devices"
  ipcTarget: "januszmajek.devices"

  // The built-in bar hands widgets a capability-scoped shell facade on
  // bar.shell; it can look up this plugin's own service and nothing else.
  readonly property var pluginShell: bar && bar.shell ? bar.shell : null
  readonly property var service: pluginShell && typeof pluginShell.serviceFor === "function"
    ? pluginShell.serviceFor("januszmajek.devices") : null
  readonly property var helperDevices: service ? service.devices : []
  readonly property var helperErrors: service ? service.errors : []

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property var btDevices: Bluetooth.devices ? Bluetooth.devices.values : []
  readonly property var btPaired: btDevices.filter(d => d.paired || d.bonded || d.trusted)
  readonly property var btDiscovered: btDevices.filter(d => !(d.paired || d.bonded || d.trusted) && Model.hasHumanName(d))

  readonly property int lowBattery: Number(setting("lowBattery", 20))
  readonly property var batteries: Model.batteries(helperDevices, btDevices)
  readonly property var weakest: batteries.length ? batteries[0] : null
  readonly property bool low: weakest !== null && weakest.level <= lowBattery

  // Which helper device has its settings open.
  property string expandedId: ""
  // True while this panel owes BlueZ a StopDiscovery (see the Bluetooth panel).
  property bool owesDiscoveryStop: false
  property var pendingBt: ({})

  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Commons.Color.accent) : "transparent"
  readonly property color dimmed: bar ? Qt.darker(bar.foreground, 1.5) : "gray"

  visible: helperDevices.length > 0 || btPaired.length > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function btAction(device, action) {
    if (!device || !device.address) return
    var next = Object.assign({}, pendingBt)
    next[device.address] = action
    pendingBt = next
    pendingBtClear.restart()
    Quickshell.execDetached(["omarchy-bluetooth-device", action, device.address])
  }

  function toggleBt(device) {
    if (device.connected) btAction(device, "disconnect")
    else btAction(device, device.paired || device.bonded || device.trusted ? "connect" : "pair")
  }

  function setScanning(on) {
    if (!adapter) return
    if (on) owesDiscoveryStop = true
    adapter.discovering = on
  }

  onOpenedChanged: {
    if (opened) {
      if (service) service.refresh()
    } else if (owesDiscoveryStop && adapter && adapter.discovering) {
      adapter.discovering = false
      owesDiscoveryStop = false
    }
  }

  onBtDevicesChanged: {
    // Drop pending labels once BlueZ reports the result.
    var next = Object.assign({}, pendingBt), changed = false
    for (var address in next) {
      var d = btDevices.find(x => x.address === address)
      var action = next[address]
      if (!d || (action === "connect" && d.connected) || (action === "pair" && d.connected)
          || (action === "disconnect" && !d.connected) || (action === "forget" && !d.paired)) {
        delete next[address]
        changed = true
      }
    }
    if (changed) pendingBt = next
  }

  Timer {
    id: pendingBtClear
    interval: 20000
    onTriggered: root.pendingBt = ({})
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.icon(root.weakest ? root.weakest.kind : "mouse")
      + (root.weakest && root.setting("showPercent", true) ? " " + root.weakest.level + "%" : "")
    active: root.low
    tooltipText: root.batteries.map(b => b.name + ": " + b.level + "%" + (b.charging ? " (charging)" : "")).join("\n")
      || "Devices"
    onPressed: function(b) {
      if (b === Qt.RightButton) { if (root.service) root.service.refresh() }
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: parent.width
          spacing: Style.space(12)

          // ---------- Hero ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroText.implicitHeight)

            Text {
              id: heroIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: Model.icon("mouse")
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
            }

            Column {
              id: heroText
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: refreshButton.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Devices"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                text: (!root.service ? "SERVICE NOT RUNNING"
                  : !root.service.ready ? "SCANNING…"
                  : root.weakest ? "LOWEST: " + root.weakest.name.toUpperCase() + " " + root.weakest.level + "%"
                  : "NO BATTERY READINGS")
                color: root.low ? root.bar.urgent : root.dimmed
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }

            PanelActionButton {
              id: refreshButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰑐"
              tooltipText: "Refresh"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: if (root.service) root.service.refresh()
            }
          }

          Text {
            visible: text !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: [root.service ? root.service.lastError : ""].concat(root.helperErrors).filter(e => e).join("\n")
            color: root.bar.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Receivers and USB dongles ----------
          PanelSectionHeader {
            visible: root.helperDevices.length > 0
            text: "RECEIVERS & DONGLES"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Repeater {
            model: root.helperDevices
            HelperDeviceRow {
              required property var modelData
              width: column.width
              dev: modelData
            }
          }

          PanelSeparator {
            visible: root.helperDevices.length > 0 && !!root.adapter
            foreground: root.bar.foreground
          }

          // ---------- Bluetooth ----------
          Item {
            visible: !!root.adapter
            width: parent.width
            implicitHeight: Math.max(btHeader.implicitHeight, btSwitch.implicitHeight)

            PanelSectionHeader {
              id: btHeader
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "BLUETOOTH"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }

            PanelActionButton {
              anchors.right: btSwitch.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              visible: root.adapter && root.adapter.enabled
              iconText: root.adapter && root.adapter.discovering ? "󰓛" : "󰍉"
              tooltipText: root.adapter && root.adapter.discovering ? "Stop scanning" : "Scan for new devices"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.setScanning(!(root.adapter && root.adapter.discovering))
            }

            ToggleSwitch {
              id: btSwitch
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: !!root.adapter && root.adapter.enabled
              foreground: root.bar.foreground
              onToggled: Quickshell.execDetached(["omarchy-bluetooth-power", root.adapter.enabled ? "off" : "on"])
            }
          }

          Repeater {
            model: root.adapter && root.adapter.enabled ? root.btPaired : []
            BluetoothRow {
              required property var modelData
              width: column.width
              dev: modelData
            }
          }

          PanelSectionHeader {
            visible: root.adapter && root.adapter.discovering
            text: root.btDiscovered.length ? "AVAILABLE — CLICK TO PAIR" : "SCANNING…"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Repeater {
            model: root.adapter && root.adapter.discovering ? root.btDiscovered : []
            BluetoothRow {
              required property var modelData
              width: column.width
              dev: modelData
            }
          }
        }
      }
    }
  }

  // ---------- Row for a receiver / dongle device, with its settings ----------
  component HelperDeviceRow: Column {
    id: hrow
    required property var dev
    readonly property bool expanded: root.expandedId === dev.id
    spacing: Style.space(6)

    CursorSurface {
      width: parent.width
      implicitHeight: hcontent.implicitHeight + Style.spacing.rowPaddingX
      foreground: root.bar.foreground
      fill: root.hoverFill
      hasCursor: hmouse.containsMouse
      current: hrow.expanded

      MouseArea {
        id: hmouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: hrow.dev.settings.length ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.expandedId = hrow.expanded ? "" : hrow.dev.id
      }

      DeviceLine {
        id: hcontent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Style.space(10)
        icon: Model.icon(hrow.dev.kind)
        name: hrow.dev.name
        status: Model.helperStatus(hrow.dev)
        online: hrow.dev.online
        trailing: hrow.dev.settings.length ? (hrow.expanded ? "󰅀" : "󰅂") : ""
      }
    }

    Column {
      visible: hrow.expanded
      width: parent.width - Style.space(20)
      x: Style.space(20)
      spacing: Style.space(8)

      Text {
        visible: !hrow.dev.online
        text: "Turn the device on or move it to change its settings."
        color: root.dimmed
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        width: parent.width
      }

      Repeater {
        model: hrow.expanded ? hrow.dev.settings : []
        SettingRow {
          required property var modelData
          width: parent.width
          dev: hrow.dev
          setting: modelData
          enabled: hrow.dev.online
          opacity: enabled ? 1 : 0.5
        }
      }
    }
  }

  // ---------- One setting: toggle, choice or range ----------
  component SettingRow: Item {
    id: srow
    required property var dev
    required property var setting
    readonly property var value: root.service ? root.service.valueFor(dev, setting) : setting.value
    implicitHeight: Math.max(slabel.implicitHeight, control.implicitHeight)

    Text {
      id: slabel
      anchors.left: parent.left
      anchors.right: control.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: srow.setting.label + (srow.setting.type === "range" ? "  " + srow.value : "")
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight

      PanelToolTip {
        visible: smouse.containsMouse && srow.setting.description !== ""
        text: srow.setting.description
        fontFamily: root.bar.fontFamily
      }
      MouseArea { id: smouse; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
    }

    Item {
      id: control
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      implicitWidth: srow.setting.type === "toggle" ? toggle.implicitWidth : Style.space(170)
      implicitHeight: srow.setting.type === "toggle" ? toggle.implicitHeight
        : srow.setting.type === "choice" ? choice.implicitHeight : slider.implicitHeight
      width: implicitWidth
      height: implicitHeight

      ToggleSwitch {
        id: toggle
        visible: srow.setting.type === "toggle"
        anchors.right: parent.right
        checked: srow.value === true
        foreground: root.bar.foreground
        onToggled: root.service.setValue(srow.dev, srow.setting.name, !(srow.value === true))
      }

      Dropdown {
        id: choice
        visible: srow.setting.type === "choice"
        width: parent.width
        showLabel: false
        fontFamily: root.bar.fontFamily
        options: srow.setting.choices || []
        value: String(srow.value)
        onChanged: function(v) { if (v !== String(srow.value)) root.service.setValue(srow.dev, srow.setting.name, v) }
      }

      PanelSlider {
        id: slider
        visible: srow.setting.type === "range"
        width: parent.width
        anchors.verticalCenter: parent.verticalCenter
        bar: root.bar
        integer: true
        step: 1
        minimum: srow.setting.min !== undefined ? srow.setting.min : 0
        maximum: srow.setting.max !== undefined ? srow.setting.max : 100
        value: Number(srow.value)
        onReleased: function(v) { if (Math.round(v) !== Number(srow.value)) root.service.setValue(srow.dev, srow.setting.name, Math.round(v)) }
      }
    }
  }

  // ---------- Bluetooth device row ----------
  component BluetoothRow: CursorSurface {
    id: brow
    required property var dev
    readonly property string pendingAction: root.pendingBt[dev.address] || ""
    readonly property bool known: dev.paired || dev.bonded || dev.trusted
    implicitHeight: bcontent.implicitHeight + Style.spacing.rowPaddingX
    foreground: root.bar.foreground
    fill: root.hoverFill
    hasCursor: bmouse.containsMouse
    current: dev.connected

    MouseArea {
      id: bmouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggleBt(brow.dev)
    }

    PanelToolTip {
      visible: bmouse.containsMouse && !forget.containsMouseish
      text: brow.dev.connected ? "Disconnect" : brow.known ? "Connect" : "Pair"
      fontFamily: root.bar.fontFamily
    }

    DeviceLine {
      id: bcontent
      anchors.left: parent.left
      anchors.right: forget.visible ? forget.left : parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Style.space(10)
      icon: Model.icon(Model.bluetoothKind(brow.dev))
      name: Model.deviceLabel(brow.dev)
      status: Model.bluetoothStatus(brow.dev, brow.pendingAction)
      online: brow.dev.connected
    }

    PanelActionButton {
      id: forget
      property bool containsMouseish: false
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      visible: brow.known && (bmouse.containsMouse || containsMouseish)
      iconText: "󰅙"
      tooltipText: "Forget"
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
      onHovered: function(h) { containsMouseish = h }
      onClicked: root.btAction(brow.dev, "forget")
    }
  }

  // ---------- Shared icon · name · status line ----------
  component DeviceLine: Item {
    property string icon: ""
    property string name: ""
    property string status: ""
    property string trailing: ""
    property bool online: true
    implicitHeight: Math.max(lineIcon.implicitHeight, lineText.implicitHeight)

    Text {
      id: lineIcon
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(26)
      text: parent.icon
      color: parent.online ? root.bar.foreground : root.dimmed
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.heading
    }

    Column {
      id: lineText
      anchors.left: lineIcon.right
      anchors.leftMargin: Style.space(8)
      anchors.right: lineTrailing.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        text: parent.parent.name
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        width: parent.width
      }
      Text {
        visible: text !== ""
        text: parent.parent.status
        color: root.dimmed
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: parent.width
      }
    }

    Text {
      id: lineTrailing
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: parent.trailing
      color: root.dimmed
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }
  }
}
