import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Todo (kosovim-dev.todo) — a compact task tracker for Omarchy.
//
// Bar pill: pending-task count. Click toggles the popup panel.
// The data file lives at ~/.local/state/omarchy/kosovim-dev.todo/data.json
// and is managed by a FileView + JsonAdapter, which reads on load and
// writes atomically whenever the tasks array changes — so the list survives
// shell restarts.
//
// Tunables (per-widget in ~/.config/omarchy/shell.json):
//   { "id": "kosovim-dev.todo", "maxShown": 12, "dataFile": ".../data.json" }

BarWidget {
  id: root
  moduleName: "kosovim-dev.todo"

  readonly property string home: Quickshell.env("HOME")
  // Runtime state lives outside the watched plugins dir so writing it never
  // trips the shell's dev hot-reload watcher (which would reload all plugins).
  function resolveDataFile(configured, fallback) {
    var p = String(configured || "").trim()
    if (!p) p = fallback
    if (p.indexOf("~/") === 0 || p === "~") p = home + p.slice(1)
    return p
  }
  readonly property string dataPath: resolveDataFile(setting("dataFile", ""),
    home + "/.local/state/omarchy/kosovim-dev.todo/data.json")
  readonly property int maxShown: Math.max(3, Number(setting("maxShown", 12)))
  readonly property int panelWidth: Style.space(300)

  // ---- Shared task store --------------------------------------------
  // Plain JS array of { id, text, completed }. Mutations replace the whole
  // array (or the entry in it) so the `tasks` binding trips and persists.
  property var tasks: []

  readonly property int remainingCount: {
    var n = 0
    for (var i = 0; i < tasks.length; i++) if (!tasks[i].completed) n++
    return n
  }

  function nextId() {
    var max = 0
    for (var i = 0; i < tasks.length; i++) {
      var id = Number(tasks[i].id)
      if (isFinite(id) && id > max) max = id
    }
    return max + 1
  }

  function addTask(text) {
    var clean = String(text || "").trim()
    if (!clean) return
    var next = tasks.slice()
    next.push({ id: root.nextId(), text: clean, completed: false, priority: false })
    root.tasks = next
  }

  function toggleTask(id) {
    var next = tasks.slice()
    for (var i = 0; i < next.length; i++) {
      if (next[i].id === id) {
        next[i] = { id: next[i].id, text: next[i].text, completed: !next[i].completed, priority: next[i].priority === true }
        break
      }
    }
    root.tasks = next
  }

  function togglePriority(id) {
    var next = tasks.slice()
    for (var i = 0; i < next.length; i++) {
      if (next[i].id === id) {
        next[i] = { id: next[i].id, text: next[i].text, completed: next[i].completed === true, priority: next[i].priority !== true }
        break
      }
    }
    root.tasks = next
  }

  function removeTask(id) {
    root.tasks = tasks.filter(function(t) { return t.id !== id })
  }

  function renameTask(id, text) {
    var clean = String(text || "").trim()
    if (!clean) return
    var next = tasks.slice()
    for (var i = 0; i < next.length; i++) {
      if (next[i].id === id) {
        if (next[i].text === clean) return
        next[i] = { id: next[i].id, text: clean, completed: next[i].completed === true, priority: next[i].priority === true }
        break
      }
    }
    root.tasks = next
  }

  function clearCompleted() {
    root.tasks = tasks.filter(function(t) { return !t.completed })
  }

  // ---- Data file recovery -------------------------------------------
  // A corrupt data.json is not a reason to take the shell down: we surface
  // the error and fall back to an empty list (see onLoadFailed / onSaveFailed).
  property string fileError: ""
  property bool fileReady: fileView.loaded

  // ---- Panel plumbing ------------------------------------------------
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("store" in target) target.store = root
  }

  IpcHandler {
    target: "kosovim-dev.todo"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // ---- Bar pill: checkbox glyph + pending count badge -----------------
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u2610"
    labelVisible: true
    tooltipText: root.remainingCount > 0
      ? "Todo — " + root.remainingCount + " pending"
      : "Todo"
    active: root.opened
    onPressed: function() { root.togglePanel() }

    Text {
      id: countBadge
      text: String(root.remainingCount)
      visible: root.remainingCount > 0
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: Style.spaceReal(1)
      anchors.rightMargin: Style.spaceReal(-1)
      color: button.foreground
      font.family: button.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      renderType: Text.NativeRendering
    }
  }

  // ---- JSON persistence ----------------------------------------------
  // Reads the tasks array in from data.json on startup and writes it back
  // on every change, atomically. watchChanges reloads if the file is edited
  // on disk (e.g. by another tool).
  //
  // Ensure the parent dir exists before any write. The state dir is outside
  // the watched plugins dir, so writes never trip the shell's hot reload.
  Process {
    id: ensureDataDir
    command: ["bash", "-c", "mkdir -p \"$1\"", "kosovim-dev.todo", root.dataPath.replace(/\/[^/]*$/, "")]
    running: true
  }

  FileView {
    id: fileView
    path: root.dataPath
    atomicWrites: true
    watchChanges: true
    onFileChanged: reload()
    onAdapterUpdated: writeAdapter()
    onLoadFailed: function(error) {
      // Missing file is normal on first run (JsonAdapter starts empty).
      // Any other failure is surfaced to the panel as an error state.
      if (error !== FileViewError.FileNotFound) root.fileError = "Failed to read " + root.dataPath
    }
    onSaveFailed: root.fileError = "Failed to write " + root.dataPath

    JsonAdapter {
      id: adapter
      property var tasks: []
      onTasksChanged: root.tasks = tasks
    }
  }

  // Push in-memory changes out to the adapter, which trips onAdapterUpdated
  // and writes the file. The equality guard prevents a load/bind echo loop.
  onTasksChanged: {
    if (JSON.stringify(adapter.tasks) !== JSON.stringify(root.tasks)) {
      adapter.tasks = root.tasks
    }
  }
}
