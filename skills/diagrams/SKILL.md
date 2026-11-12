---
name: diagrams
description: >
  Create or update Excalidraw diagrams with useful conversation context in a
  Markdown note. Use for architecture sketches, flows, sequences, states,
  data models, or visual explanations. Use Mermaid only when explicitly requested.
---

# Diagrams

## Choose the Note

- Honor an explicitly requested destination. For an ongoing topic, update the
  existing note and keep its path stable.
- Otherwise use `$DIAGRAM_NOTES_DIR/<project>/<topic>-<short-id>.md`.
  If unset, use `$TMPDIR/diagram-notes`, falling back to the system temporary
  directory plus `diagram-notes`. Use short slugs, check for collisions, and
  create parent directories as needed.
- Store scenes and PNGs in a sibling `<note-stem>.assets/` directory with
  matching stems, such as `overview.excalidraw` and `overview.png`.

## Draw and Explain

- Default to Excalidraw, including structured diagrams. Use Mermaid only when
  the user explicitly requests it.
- A user-specified reference note takes precedence over the style defaults below.
  Copy typography, stroke colours and widths, roughness, opacity, fills, and
  corner settings from its actual scene elements, matching element roles.
  Preserve meaningful dashed relationships. Compare the rendered results;
  do not approximate the reference by changing only selected style properties.
- Use the hand-drawn style by default: Excalifont (`fontFamily: 5`) for every
  text element, `roughness: 1` and `strokeWidth: 2` for visible shapes and
  connectors. Start labels at `fontSize: 20`, adjusting size and wrapping to fit.
  Use solid strokes unless dashed strokes convey a relationship. Only use
  another visual style when the user explicitly requests it.
- Round corners by default: set rectangles' `roundness` to `{ "type": 3 }`
  and diamonds' to `{ "type": 2 }`. Set `appState.currentItemRoundness` to
  `"round"` for continued editing. Keep rounded connectors where supported.
- Apply these settings to the actual elements, including imported/generated
  scenes; `appState.currentItem*` settings affect only newly drawn elements.
  A handwritten font alone does not make outlines hand-drawn. Preserve semantic
  colours, connector styles, layout, and IDs when normalising an existing scene.
- Establish the relationships from the conversation and relevant source files.
  Label assumptions and distinguish current behavior from proposals.
- Focus each drawing on one question. Use concise labels, consistent reading
  direction, and stable element IDs. Preserve useful layout when updating scenes.
- Set every element's `backgroundColor` to `"transparent"`. Use outlines and
  labels, with a small accent palette; avoid filled containers and canvas-sized
  background rectangles. Check readability against a dark background.
- Start the note with a descriptive heading. Embed each PNG with a brief
  explanation and a separate link to its editable scene. Use relative links:

```markdown
# Request Flow

![Request flow](request-flow-a1b2.assets/overview.png)

[Drawing source](request-flow-a1b2.assets/overview.excalidraw)

The API validates the request before sending it to the worker.
```

- Distill relevant decisions, reasons, constraints, and open questions alongside
  the diagrams. Preserve useful context as the note evolves.

## Render and Hand Off

- Render each scene with:
  `excalidraw render overview.excalidraw --out overview.png --scale 2 --transparent --theme dark`.
  If the command is unavailable, use
  `npx --yes --package=@excalidraw/cli@0.3.0 excalidraw` as its prefix.
- `--transparent` removes only the canvas; element fills must also be transparent.
  Let the dark export theme adapt scene colours.
- Read the note back, check scene/image links, render, and inspect the result.
  Verify typography, outlines, corner settings, text fit, and transparency
  against the chosen style. When matching another note, inspect its scene settings
  and rendered image rather than guessing a font or relying on renderer defaults.
  Fix errors before handing off; report any rendering check you could not perform.
  For requested Mermaid, validate its fenced blocks and syntax instead.
- Return the absolute note path and a ready-to-paste `:vsplit <absolute-path>`
  command, escaping special characters for Neovim's filename syntax.
