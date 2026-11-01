import QtQuick
import QtQuick.Controls
import Quickshell
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

  readonly property var devices: service ? service.devices : []
  readonly property var batteries: service ? service.batteries : []
  readonly property var lowDevices: service ? service.lowDevices : []
  readonly property bool low: lowDevices.length > 0
  readonly property int lowBattery: Number(setting("lowBattery", 20))

  // Which device has its settings open.
  property string expandedId: ""

  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Commons.Color.accent) : "transparent"
  readonly property color dimmed: bar ? Qt.darker(bar.foreground, 1.5) : "gray"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Binding {
    target: root.service
    when: root.service !== null
    property: "lowBattery"
    value: root.lowBattery
  }

  onOpenedChanged: if (opened && service) service.refresh()

  function isLow(dev) {
    return dev.online && !dev.charging && dev.battery !== null && dev.battery !== undefined && dev.battery <= lowBattery
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.icon("devices") + (root.low ? " " + Model.icon("batteryAlert") : "")
    active: root.low
    tooltipText: Model.tooltip(root.lowDevices, root.batteries)
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
              text: Model.icon("devices")
              color: root.low ? root.bar.urgent : root.bar.foreground
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
                text: !root.service ? "SERVICE NOT RUNNING"
                  : root.low ? root.lowDevices.length + " LOW ON BATTERY"
                  : !root.service.ready ? "SCANNING…"
                  : root.devices.filter(d => d.online).length + " CONNECTED"
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
            text: root.service ? [root.service.lastError].concat(root.service.errors).filter(e => e).join("\n") : ""
            color: root.bar.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          PanelSeparator { foreground: root.bar.foreground }

          Repeater {
            model: root.devices
            DeviceRow {
              required property var modelData
              width: column.width
              dev: modelData
            }
          }

          Text {
            visible: root.devices.length === 0
            text: root.service && !root.service.ready ? "Looking for devices…" : "No wireless devices found"
            color: root.dimmed
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }

  // ---------- One device, with its settings when expanded ----------
  component DeviceRow: Column {
    id: drow
    required property var dev
    readonly property bool expandable: dev.settings.length > 0
    readonly property bool expanded: expandable && root.expandedId === dev.id
    readonly property bool lowNow: root.isLow(dev)
    spacing: Style.space(6)

    CursorSurface {
      width: parent.width
      implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX
      foreground: root.bar.foreground
      fill: root.hoverFill
      hasCursor: rowMouse.containsMouse
      current: drow.expanded

      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: drow.expandable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (drow.expandable) root.expandedId = drow.expanded ? "" : drow.dev.id
      }

      Item {
        id: rowContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        implicitHeight: Math.max(kindIcon.implicitHeight, info.implicitHeight, badge.implicitHeight)

        Text {
          id: kindIcon
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(26)
          text: Model.icon(drow.dev.kind)
          color: drow.lowNow ? root.bar.urgent : drow.dev.online ? root.bar.foreground : root.dimmed
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.heading
        }

        Column {
          id: info
          anchors.left: kindIcon.right
          anchors.leftMargin: Style.space(8)
          anchors.right: badge.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(1)

          Text {
            text: drow.dev.name
            color: drow.dev.online ? root.bar.foreground : root.dimmed
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
            width: parent.width
          }
          Text {
            text: Model.status(drow.dev)
            color: drow.lowNow ? root.bar.urgent : root.dimmed
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: drow.lowNow
            elide: Text.ElideRight
            width: parent.width
          }
          Text {
            visible: drow.dev.online && !!drow.dev.mic
            text: (Model.micMuted(drow.dev.mic) ? Model.icon("micOff") : Model.icon("mic")) + " " + Model.micText(drow.dev.mic)
            color: Model.micMuted(drow.dev.mic) ? root.bar.urgent : root.dimmed
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
          }
        }

        // How the device reaches this computer.
        Rectangle {
          id: badge
          anchors.right: chevron.left
          anchors.rightMargin: chevron.text ? Style.space(8) : 0
          anchors.verticalCenter: parent.verticalCenter
          implicitWidth: badgeText.implicitWidth + Style.space(12)
          implicitHeight: badgeText.implicitHeight + Style.space(4)
          radius: Style.cornerRadius > 0 ? height / 2 : 0
          color: "transparent"
          border.width: 1
          border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.25)

          Text {
            id: badgeText
            anchors.centerIn: parent
            text: drow.dev.connection
            color: root.dimmed
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          id: chevron
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: drow.expandable ? (drow.expanded ? "󰅀" : "󰅂") : ""
          color: root.dimmed
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
        }
      }
    }

    Column {
      visible: drow.expanded
      width: parent.width - Style.space(20)
      x: Style.space(20)
      spacing: Style.space(8)

      Text {
        visible: !drow.dev.online
        text: "Turn the device on or move it to change its settings."
        color: root.dimmed
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        width: parent.width
      }

      Repeater {
        model: drow.expanded ? drow.dev.settings : []
        SettingRow {
          required property var modelData
          width: parent.width
          dev: drow.dev
          setting: modelData
          enabled: drow.dev.online
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
}
