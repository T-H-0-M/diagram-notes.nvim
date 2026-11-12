local M = {}
local configured = false

function M.setup(opts)
	local preview = require("diagram_notes.preview")
	require("diagram_notes.config").setup(opts)
	preview.close()
	preview.setup()
	M.commands()
	configured = true
end

local function ensure_setup()
	if not configured then
		M.setup()
	end
end

function M.notes()
	ensure_setup()
	return require("diagram_notes.notes").open()
end

function M.toggle()
	ensure_setup()
	return require("diagram_notes.preview").toggle()
end

function M.zoom()
	ensure_setup()
	return require("diagram_notes.preview").zoom()
end

function M.render()
	ensure_setup()
	return require("diagram_notes.preview").render()
end

function M.close()
	return require("diagram_notes.preview").close()
end

function M.export(path)
	ensure_setup()
	return require("diagram_notes.export").buffer(require("diagram_notes.preview").source(), path)
end

function M.commands()
	vim.api.nvim_create_user_command("DiagramNotes", M.notes, { desc = "Browse diagram notes beside your code" })
	vim.api.nvim_create_user_command("DiagramPreview", M.toggle, { desc = "Toggle diagram note source/preview" })
	vim.api.nvim_create_user_command("DiagramZoom", M.zoom, { desc = "Inspect the selected diagram full-screen" })
	vim.api.nvim_create_user_command("ExcalidrawRender", M.render, { desc = "Regenerate the note's Excalidraw images" })
	vim.api.nvim_create_user_command("DiagramExport", function(opts)
		M.export(opts.fargs[1])
	end, { nargs = "?", complete = "file", desc = "Export the note to PDF (default: ~/Downloads)" })
	vim.keymap.set("n", "<leader>ex", "<cmd>DiagramExport<cr>", { desc = "Export note to PDF" })
end

return M
