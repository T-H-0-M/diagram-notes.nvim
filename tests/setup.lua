local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
local h = dofile(root .. "/tests/helpers.lua")
local config = require("diagram_notes.config")
local plugin = require("diagram_notes")
local environment = { notes = vim.env.DIAGRAM_NOTES_DIR, temporary = vim.env.TMPDIR }
local function cleanup()
	vim.env.DIAGRAM_NOTES_DIR, vim.env.TMPDIR = environment.notes, environment.temporary
	plugin.close()
	config.setup()
end

h.test("the shared environment selects the notes directory", function()
	vim.env.DIAGRAM_NOTES_DIR = root .. "/environment-notes"
	plugin.setup()
	h.equal(vim.env.DIAGRAM_NOTES_DIR, config.get().notes_dir)
end, cleanup)

h.test("an explicit directory takes precedence over the shared environment", function()
	vim.env.DIAGRAM_NOTES_DIR = root .. "/environment-notes"
	plugin.setup({ notes_dir = root .. "/configured-notes" })
	h.equal(root .. "/configured-notes", config.get().notes_dir)
end, cleanup)

h.test("the default directory is agent-neutral and uses the operating system temp root", function()
	vim.env.DIAGRAM_NOTES_DIR, vim.env.TMPDIR = nil, nil
	plugin.setup()
	h.equal(vim.fs.abspath(vim.fs.joinpath(vim.uv.os_tmpdir(), "diagram-notes")), config.get().notes_dir)
end, cleanup)

h.test("repeated setup replaces previous settings without duplicate lifecycle handlers", function()
	plugin.setup({ render = { theme = "light", scale = 3 } })
	plugin.setup({ picker = "select" })
	h.equal("dark", config.get().render.theme)
	h.equal(2, config.get().render.scale)
	h.equal(2, #vim.api.nvim_get_autocmds({ group = "DiagramNotesPreview" }))
end, cleanup)

h.test("setup registers commands and the PDF export leader mapping", function()
	plugin.setup()
	h.equal(2, vim.fn.exists(":DiagramNotes"))
	h.equal(2, vim.fn.exists(":DiagramPreview"))
	h.equal(2, vim.fn.exists(":DiagramZoom"))
	h.equal(2, vim.fn.exists(":ExcalidrawRender"))
	h.equal(2, vim.fn.exists(":DiagramExport"))
	h.equal("<Cmd>DiagramExport<CR>", vim.fn.maparg("<leader>ex", "n"))
end, cleanup)

h.test("invalid configuration is rejected without replacing the working settings", function()
	plugin.setup({ render = { theme = "light" } })
	local ok, err = pcall(plugin.setup, { render = { scale = 0 } })
	h.equal(false, ok)
	assert(tostring(err):find("render.scale", 1, true))
	h.equal("light", config.get().render.theme)
end, cleanup)

h.finish()
