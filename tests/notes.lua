local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.o.hidden = true
local h = dofile(root .. "/tests/helpers.lua")
local notes = require("diagram_notes.notes")
local config = require("diagram_notes.config")
local select, notify = vim.ui.select, vim.notify
local loaded, preload = package.loaded.snacks, package.preload.snacks

local function test(name, body)
	local directory = vim.fn.tempname()
	vim.fn.mkdir(directory .. "/project/note.assets", "p")
	directory = assert(vim.uv.fs_realpath(directory))
	local note = directory .. "/project/note with spaces.md"
	vim.fn.writefile({ "# A note" }, note)
	vim.fn.writefile({ "image" }, directory .. "/project/note.assets/overview.png")
	vim.fn.writefile({ "{}" }, directory .. "/project/note.assets/overview.excalidraw")
	vim.cmd("enew!")
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "application code" })
	local ctx = {
		directory = directory,
		note = note,
		win = vim.api.nvim_get_current_win(),
		buf = vim.api.nvim_get_current_buf(),
		notices = {},
	}
	package.loaded.snacks = nil
	package.preload.snacks = function()
		error("Snacks is not installed")
	end
	vim.ui.select = function(items, opts, callback)
		ctx.items, ctx.options, ctx.choose = items, opts, callback
	end
	vim.notify = function(message)
		ctx.notices[#ctx.notices + 1] = message
	end
	config.setup({ notes_dir = directory })
	h.test(name, function()
		body(ctx)
	end, function()
		vim.ui.select, vim.notify = select, notify
		package.loaded.snacks, package.preload.snacks = loaded, preload
		vim.cmd("silent! only!")
		vim.cmd("enew!")
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if buf ~= vim.api.nvim_get_current_buf() then
				pcall(vim.api.nvim_buf_delete, buf, { force = true })
			end
		end
		vim.fn.delete(directory, "rf")
	end)
end

test("auto discovery falls back to Markdown-only selection without Snacks", function(ctx)
	notes.open()
	h.equal({ ctx.note }, ctx.items)
	h.equal("project/note with spaces.md", ctx.options.format_item(ctx.note))
end)

test("fallback selection opens a split beside the original unsaved code buffer", function(ctx)
	notes.open()
	ctx.choose(ctx.note)
	h.equal(ctx.note, vim.api.nvim_buf_get_name(0))
	assert(vim.api.nvim_get_current_win() ~= ctx.win)
	h.equal(ctx.buf, vim.api.nvim_win_get_buf(ctx.win))
	h.equal(true, vim.bo[ctx.buf].modified)
	h.equal(2, #vim.api.nvim_tabpage_list_wins(0))
end)

test("cancelled selection leaves the original window untouched", function(ctx)
	notes.open()
	ctx.choose(nil)
	h.equal(ctx.win, vim.api.nvim_get_current_win())
	h.equal(ctx.buf, vim.api.nvim_get_current_buf())
	h.equal(1, #vim.api.nvim_tabpage_list_wins(0))
end)

test("Snacks discovery enables file previews and vertical split confirmation", function(ctx)
	local selected
	package.loaded.snacks = { picker = {
		pick = function(opts)
			selected = opts
		end,
	} }
	notes.open()
	h.equal(ctx.directory, selected.cwd)
	h.equal("md", selected.ft)
	h.equal("file", selected.preview)
	h.equal(true, selected.layout.preview)
	h.equal({ action = "jump", cmd = "vsplit" }, selected.confirm)
	h.equal(nil, ctx.items)
end)

test("an explicitly selected Snacks picker reports a missing dependency", function(ctx)
	config.setup({ notes_dir = ctx.directory, picker = "snacks" })
	notes.open()
	h.equal(nil, ctx.items)
	assert(ctx.notices[1]:find("Install snacks.nvim", 1, true))
end)

test("a missing notes directory explains where new notes should go", function(ctx)
	config.setup({ notes_dir = ctx.directory .. "/missing" })
	notes.open()
	h.equal(nil, ctx.items)
	assert(ctx.notices[1]:find(ctx.directory .. "/missing", 1, true))
end)

h.finish()
