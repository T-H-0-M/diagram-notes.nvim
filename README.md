# diagram-notes.nvim

Agent-authored diagrams beside your code: browse Markdown notes, preview Excalidraw
images, and watch updates without losing your editor layout or unsaved changes.
Exports use transparent shapes and dark-theme colours.

## Requirements

Neovim 0.12+, Markdown Tree-sitter parsers, [Vellum](https://github.com/blackhat-7/vellum.nvim),
and Ghostty or Kitty with true colour. Excalidraw export requires Node.js 22+, npm,
and an installed Chrome, Chromium, Edge, or Firefox. Snacks is optional.

## Install

With lazy.nvim, using a local checkout:

```lua
{
  dir = "/path/to/diagram-notes.nvim",
  main = "diagram_notes",
  dependencies = { "blackhat-7/vellum.nvim" },
  opts = {},
  keys = {
    { "<leader>dn", "<cmd>DiagramNotes<cr>", desc = "Diagram notes" },
    { "<leader>mv", "<cmd>DiagramPreview<cr>", desc = "Diagram preview" },
    { "<leader>mz", "<cmd>DiagramZoom<cr>", desc = "Zoom diagram" },
    { "<leader>mr", "<cmd>ExcalidrawRender<cr>", desc = "Render diagrams" },
  },
}
```

| Command | Action |
| --- | --- |
| `:DiagramNotes` | Pick a note and open it in a vertical split |
| `:DiagramPreview` | Toggle source/preview in the same pane |
| `:DiagramZoom` | Inspect the selected diagram full-screen |
| `:ExcalidrawRender` | Regenerate the note's PNGs |

In the Snacks picker, press `<C-x>` to delete the highlighted note and its matching
`.assets/` directory. With the fallback picker, choose **Delete note…**, then the
note. Deletion is immediate; unsaved edits in the note or its assets block deletion.

## Agent skill

Link or copy [`skills/diagrams`](skills/diagrams) into your agent's skills directory.
It defaults to Excalidraw and includes useful conversation context in each note.
Set `DIAGRAM_NOTES_DIR` in the environment shared by Neovim and your agent to choose
a notes directory; otherwise both use `$TMPDIR/diagram-notes` (system temp fallback).

See `:help diagram-notes` for configuration, controls, and development checks.
Run `:checkhealth diagram_notes` to diagnose setup problems.
