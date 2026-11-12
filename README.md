# diagram-notes.nvim

Agent-authored diagrams beside your code: browse Markdown notes, preview Excalidraw
images, and watch updates without losing your editor layout or unsaved changes.
Preview images use transparent shapes and dark-theme colours.

## Requirements

Neovim 0.12+, Markdown Tree-sitter parsers, [Vellum](https://github.com/blackhat-7/vellum.nvim),
and Ghostty or Kitty with true colour. Excalidraw export requires Node.js 22+, npm,
and an installed Chrome, Chromium, Edge, or Firefox. Snacks is optional.
PDF export also requires Vellum's browser renderer: run `:Vellum build` once.

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
    { "<leader>ex", "<cmd>DiagramExport<cr>", desc = "Export note to PDF" },
  },
}
```

| Command | Action |
| --- | --- |
| `:DiagramNotes` | Pick a note and open it in a vertical split |
| `:DiagramPreview` | Toggle source/preview in the same pane |
| `:DiagramZoom` | Inspect the selected diagram full-screen |
| `:ExcalidrawRender` | Regenerate the note's PNGs |
| `:DiagramExport [path.pdf]` | Export the source or previewed note to PDF |

Press `<leader>ex` to export to `~/Downloads/<note-stem>.pdf`. Supply a path to
`:DiagramExport` for a different destination. Exports include unsaved Markdown and
use light-theme diagram images for readable PDFs. An existing PDF is replaced
after export succeeds.

In the Snacks picker, `e` in normal mode exports the highlighted note. The fallback
picker offers **Export note…**.

In the Snacks picker, press `d` in normal mode to delete the highlighted note and
its matching `.assets/` directory. With the fallback picker, choose **Delete note…**,
then the note. Deletion is immediate; unsaved edits in the note or its assets block deletion.

## Agent skill

Link or copy [`skills/diagrams`](skills/diagrams) into your agent's skills directory.
It defaults to Excalidraw and includes useful conversation context in each note.
Set `DIAGRAM_NOTES_DIR` in the environment shared by Neovim and your agent to choose
a notes directory; otherwise both use `$TMPDIR/diagram-notes` (system temp fallback).

See `:help diagram-notes` for configuration, controls, and development checks.
Run `:checkhealth diagram_notes` to diagnose setup problems.
