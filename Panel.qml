import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Todo popup (kosovim-dev.todo): a compact task list anchored to the bar.
//
// Owns no persistence itself — everything routes through the store
// (the BarWidget root) injected by BarWidget.injectPanel(). If the data
// file could not be read or written, we show an inline error state instead
// of crashing the shell.
Panel {
  id: root
  moduleName: "kosovim-dev.todo"
  ipcTarget: "kosovim-dev.todo"
  manageIpc: false

  // The BarWidget root that owns tasks/persistence and the bar pill.
  property var store: null
  property var anchorItem: null
  property var hostWidget: null
  readonly property var storeTasks: store ? store.tasks : []

  readonly property bool hasError: store ? store.fileError !== "" : false
  readonly property string errorText: store ? store.fileError : ""
  readonly property int storeMaxShown: store ? store.maxShown : 12
  readonly property color contentForeground: Commons.Color.popups.text
  readonly property string contentFontFamily: Style.font.family

  // Cap how many rows the ListView renders at once so the popup stays
  // bounded and cheap even with a large data file. Priority tasks sort to
  // the top (stable, so otherwise the original order is kept).
  readonly property var viewTasks: {
    var arr = storeTasks.slice()
    arr.sort(function(a, b) {
      return (a.priority === true ? 0 : 1) - (b.priority === true ? 0 : 1)
    })
    return arr.slice(0, storeMaxShown)
  }

  readonly property int completedCount: {
    var n = 0
    for (var i = 0; i < storeTasks.length; i++) if (storeTasks[i].completed) n++
    return n
  }

  // Widest visible task text — drives the popup's auto width.
  readonly property string longestTaskText: {
    var max = ""
    for (var i = 0; i < viewTasks.length; i++) {
      var t = String(viewTasks[i].text || "")
      if (t.length > max.length) max = t
    }
    return max
  }

  // Fixed per-row chrome: side margins + done checkbox + the three action
  // buttons (priority, edit/save, delete) + the four gaps between elements.
  readonly property real rowControlsWidth: {
    var btn = Math.max(Style.space(22), Style.font.bodySmall + Style.spacing.sm * 2)
    return Style.spacing.xs * 2 + Style.space(16) + btn * 3 + Style.spacing.sm * 4
  }

  // Card padding + side borders; re-added when deriving contentWidth from a
  // measured natural width (see the wttrbar panel for the same trick).
  readonly property real hInset: panel.padding * 2 + Border.left(panel.borderSpec) + Border.right(panel.borderSpec)

  function addFromField() {
    if (!store) return
    root.cancelEdit()
    store.addTask(inputField.text)
    inputField.text = ""
    inputField.forceActiveFocus()
  }

  function handleInputKey(event) {
    if (event.key === Qt.Key_Escape) {
      if (inputField.text !== "") inputField.text = ""
      else root.close()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.addFromField()
      event.accepted = true
    }
  }

  // ---- inline task editing -------------------------------------------
  // A single editingId instead of per-row state keeps at most one row in
  // edit mode (the add/delete/edit/check actions all call cancelEdit first).
  property int editingId: -1

  function startEditing(id, text) {
    root.cancelEdit()
    root.editingId = id
    root.editTextBuffer = text
  }

  // Shared text buffer used while a row is being edited.
  property string editTextBuffer: ""

  function commitEdit() {
    var id = root.editingId
    if (store && id !== -1) store.renameTask(id, root.editTextBuffer)
    root.editingId = -1
    root.editTextBuffer = ""
  }

  function cancelEdit() {
    root.editingId = -1
    root.editTextBuffer = ""
  }

  function onEditKey(event) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEdit()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitEdit()
      event.accepted = true
    }
  }

  component TodoCheck: Item {
    id: box
    property bool checked: false
    property color tickColor: Commons.Color.accent
    property color stateColor: Commons.Color.accent
    readonly property int size: Style.space(16)

    signal toggled()

    implicitWidth: size
    implicitHeight: size

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius > 0 ? 3 : 0
      color: box.checked ? Style.selectedFillFor(box.stateColor, box.stateColor) : "transparent"
      border.width: box.checked ? 0 : Style.spacing.hairline
      border.color: box.checked ? box.stateColor : Style.normalBorderFor(Commons.Color.popups.text, box.stateColor)

      Behavior on color { ColorAnimation { duration: 90 } }
    }

    Text {
      visible: box.checked
      anchors.centerIn: parent
      text: "\u2713"
      color: box.tickColor
      font.family: Style.font.family
      font.bold: true
      font.pixelSize: Style.font.bodySmall
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      cursorShape: Qt.PointingHandCursor
      onClicked: box.toggled()
    }
  }

  function close() { root.controller.hide() }

  // Measure the widest task line (single-line text; NoWrap reports the true
  // width with no width constraint, so there's no binding cycle).
  Text {
    id: naturalMeasure
    visible: false
    text: root.longestTaskText
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.body
    textFormat: Text.PlainText
    wrapMode: Text.NoWrap
  }

  // ---- the popup -----------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    centerOnBar: true
    contentWidth: panel.fittedContentWidth(
      Math.max(store ? store.panelWidth : Style.space(300),
        root.hInset + root.rowControlsWidth + naturalMeasure.implicitWidth + Style.space(2)),
      (store ? store.panelWidth : Style.space(300)) * 3)
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight)
    focusTarget: keyCatcher
    onOpenChanged: {
      if (open) Qt.callLater(function() {
        if (root.opened && inputField) inputField.forceActiveFocus()
      })
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        spacing: Style.spacing.md

        // ---- header -------------------------------------------------
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm

          Text {
            text: "TODO"
            color: Qt.darker(root.contentForeground, 1.4)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
            font.bold: true
          }

          Text {
            text: root.storeTasks.length === 0
              ? "0"
              : String(root.completedCount) + "/" + root.storeTasks.length
            color: Qt.darker(root.contentForeground, 1.6)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          Item { Layout.fillWidth: true }
        }

        // ---- input row ----------------------------------------------
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.sm

          TextField {
            id: inputField
            Layout.fillWidth: true
            placeholderText: "Add a task…"
            foreground: root.contentForeground
            font.family: root.contentFontFamily
            activeFocusOnTab: true

            Keys.onPressed: function(event) { root.handleInputKey(event) }
          }

          PanelActionButton {
            id: addButton
            iconText: "\u002B"
            tooltipText: "Add task"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            focusable: true
            onClicked: root.addFromField()
          }
        }

        // ---- task list / states -------------------------------------
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.xs

          // Corrupt / unwritable data file: show the error, not the list.
          Rectangle {
            visible: root.hasError
            Layout.fillWidth: true
            Layout.preferredHeight: errorLabel.implicitHeight + Style.spacing.sm * 2
            radius: Style.cornerRadius
            color: Style.hoverFillFor(Commons.Color.urgent, Commons.Color.urgent)
            border.width: Style.spacing.hairline
            border.color: Style.normalBorderFor(Commons.Color.urgent, Commons.Color.urgent)

            Text {
              id: errorLabel
              width: parent.width - Style.spacing.sm * 2
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.sm
              anchors.top: parent.top
              anchors.topMargin: Style.spacing.sm
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              text: root.errorText !== "" ? root.errorText : "Todo data unavailable"
              color: Commons.Color.urgent
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          // Empty state.
          Text {
            visible: !root.hasError && root.storeTasks.length === 0
            Layout.fillWidth: true
            text: "No tasks yet."
            color: Qt.darker(root.contentForeground, 1.6)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
          }

          // The scrolling list.
          ListView {
            id: listView
            visible: !root.hasError && root.viewTasks.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(root.viewTasks.length, 12) * Style.spacing.popupRowHeight
            clip: true
            interactive: root.viewTasks.length > 12
            boundsBehavior: Flickable.StopAtBounds
            spacing: 0
            model: root.viewTasks

            delegate: Rectangle {
              required property var modelData
              width: listView.width
              height: Style.spacing.popupRowHeight
              radius: Style.cornerRadius
              color: mouse.containsMouse
                ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent)
                : "transparent"

              // Accent bar marking priority rows.
              Rectangle {
                visible: modelData.priority === true
                width: Style.spacing.xs
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: Style.spaceReal(1)
                anchors.topMargin: Style.spaceReal(3)
                anchors.bottomMargin: Style.spaceReal(3)
                radius: Style.cornerRadius > 0 ? Style.space(1) : 0
                color: Commons.Color.accent
              }

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.spacing.xs
                anchors.rightMargin: Style.spacing.xs
                spacing: Style.spacing.sm

                TodoCheck {
                  checked: modelData.completed === true
                  onToggled: { root.cancelEdit(); if (store) store.toggleTask(modelData.id) }
                }

                // Priority: accent when set, dimmed outline otherwise.
                PanelActionButton {
                  iconText: modelData.priority === true ? "🟊" : "\u2606"
                  tooltipText: modelData.priority === true ? "Remove priority" : "Mark priority"
                  foreground: modelData.priority === true
                    ? Commons.Color.accent
                    : Qt.darker(root.contentForeground, 1.5)
                  hoverColor: Commons.Color.accent
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.bodyLarge
                  onClicked: { root.cancelEdit(); if (store) store.togglePriority(modelData.id) }
                }

                Text {
                  visible: root.editingId !== modelData.id
                  Layout.fillWidth: true
                  text: modelData.text
                  color: modelData.completed
                    ? Qt.darker(root.contentForeground, 1.7)
                    : root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                  opacity: modelData.completed ? 0.55 : 1.0
                  textFormat: Text.PlainText

                  Rectangle {
                    visible: modelData.completed
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Style.spacing.hairline * 2
                    color: Qt.darker(root.contentForeground, 1.5)
                  }
                }

                // Inline editor for the row being edited.
                TextField {
                  visible: root.editingId === modelData.id
                  Layout.fillWidth: true
                  Layout.minimumWidth: 1
                  text: root.editTextBuffer
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  activeFocusOnTab: true
                  onTextChanged: { if (visible && root.editingId === modelData.id) root.editTextBuffer = text }
                  onVisibleChanged: { if (visible) forceActiveFocus() }
                  Keys.onPressed: function(event) { root.onEditKey(event) }
                }

                PanelActionButton {
                  visible: root.editingId !== modelData.id
                  iconText: "\uf044"
                  tooltipText: "Edit"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.bodySmall
                  onClicked: root.startEditing(modelData.id, modelData.text)
                }

                PanelActionButton {
                  visible: root.editingId === modelData.id
                  iconText: "\u2713"
                  tooltipText: "Save"
                  foreground: root.contentForeground
                  hoverColor: Commons.Color.accent
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.bodySmall
                  onClicked: root.commitEdit()
                }

                PanelActionButton {
                  iconText: "\u2715"
                  tooltipText: root.editingId === modelData.id ? "Cancel" : "Delete"
                  foreground: root.contentForeground
                  hoverColor: Commons.Color.urgent
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.bodySmall
                  onClicked: {
                    if (root.editingId === modelData.id) root.cancelEdit()
                    else if (store) store.removeTask(modelData.id)
                  }
                }
              }

              MouseArea {
                id: mouse
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                hoverEnabled: true
              }
            }
          }
        }
      }
    }
  }
}
