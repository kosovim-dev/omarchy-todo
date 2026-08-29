# Todo

A compact task tracker bar widget for Omarchy. The bar shows a pending-task
count; clicking the pill opens a popup panel for add / complete / star
(priority) / edit / delete.

## Install

```sh
omarchy plugin add https://github.com/kosovim-dev/omarchy-todo.git --enable
```

The shell hot-reloads the plugin and drops a `Todo` widget into the center of
the bar. Move or tune it from `~/.config/omarchy/shell.json`, e.g. into the
`right` section next to the network pill:

```json
{
  "id": "kosovim-dev.todo",
  "dataFile": "~/.local/state/omarchy/kosovim-dev.todo/data.json"
}
```

## Usage

- **Click** the bar pill (☐) to toggle the panel; a badge shows pending tasks.
- **Keyboard** enter creates a task / saves an edit, Esc closes the panel
  (in edit mode Esc cancels the edit first).
- **Buttons per row**: click a row toggles its check, ⭐ toggles priority
  (priority rows sort to the top and get an accent bar), ✎ edits inline, 🗑
  removes.
- Completed tasks stay visible with a strikethrough so you can keep the day's
  history.

## Tunables

| Setting      | Default                                  | Meaning                                        |
| ------------ | ---------------------------------------- | ---------------------------------------------- |
| `dataFile`   | `~/.local/state/omarchy/kosovim-dev.todo/data.json` | Where tasks are stored. `~` is expanded. |
| `maxShown`   | `12`                                     | Max rows in the panel before it scrolls.       |

Set them per-widget in `shell.json` (see Install). The panel width auto-fits
the longest row, from 300px up to 900px.

## Notes

- Tasks persist as a small JSON file under `~/.local/state/omarchy/`, *outside*
  the watched plugins dir — writing a task never trips the shell's dev
  hot-reload watcher, and the file is written atomically.
- The data file is plain JSON: `{ "tasks": [ { "id", "text", "completed",
  "priority" } ] }`. Editing it on disk reloads the panel live.

## IPC

While the shell is running, `kosovim-dev.todo` exposes `open`, `close`, `show`,
`hide`, and `toggle` (e.g. map it to a keybind or use it from a script).

## License

MIT — see [LICENSE](LICENSE).