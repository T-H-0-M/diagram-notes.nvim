local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.o.hidden = true
local h = dofile(root .. "/tests/helpers.lua")
local notes = require("diagram_notes.notes")
local config = require("diagram_notes.config")
local select, notify = vim.ui.select, vim.notify
local loaded, preload = package.loaded.snacks, package.preload.snacks
local delete, unlink = vim.fn.delete, vim.uv.fs_unlink
local exporter = package.loaded["diagram_notes.export"]

local function test(name, body)
	local directory = vim.fn.tempname()
	vim.fn.mkdir(directory .. "/project/note with spaces.assets", "p")
	directory = assert(vim.uv.fs_realpath(directory))
	local note = directory .. "/project/note with spaces.md"
	local assets = directory .. "/project/note with spaces.assets"
	vim.fn.writefile({ "# A note" }, note)
	vim.fn.writefile({ "image" }, assets .. "/overview.png")
	vim.fn.writefile({ "{}" }, assets .. "/overview.excalidraw")
	vim.cmd("enew!")
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "application code" })
	local ctx = {
		directory = directory,
		note = note,
		assets = assets,
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
		vim.fn.delete, vim.uv.fs_unlink = delete, unlink
		package.loaded.snacks, package.preload.snacks = loaded, preload
		package.loaded["diagram_notes.export"] = exporter
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
	h.equal(3, #ctx.items)
	h.equal(ctx.note, ctx.items[1])
	h.equal("project/note with spaces.md", ctx.options.format_item(ctx.note))
	h.equal("Export note…", ctx.options.format_item(ctx.items[2]))
	h.equal("Delete note…", ctx.options.format_item(ctx.items[3]))
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
	h.equal("delete_note", selected.win.input.keys.d[1])
	h.equal("n", selected.win.input.keys.d.mode)
	h.equal("delete_note", selected.win.list.keys.d[1])
	h.equal("n", selected.win.list.keys.d.mode)
	h.equal("export_note", selected.win.input.keys.e[1])
	h.equal("n", selected.win.input.keys.e.mode)
	h.equal("export_note", selected.win.list.keys.e[1])
	h.equal(nil, ctx.items)
end)

test("deletion removes the note bundle with spaces while preserving linked shared assets", function(ctx)
	local shared = ctx.directory .. "/shared.png"
	vim.fn.writefile({ "shared" }, shared)
	vim.fn.writefile({ "![Shared](../shared.png)" }, ctx.note)
	local deleted = notes.delete(ctx.note)
	h.equal(true, deleted)
	h.equal(nil, vim.uv.fs_stat(ctx.note))
	h.equal(nil, vim.uv.fs_stat(ctx.assets))
	h.equal({ "shared" }, vim.fn.readfile(shared))
end)

test("a note without an assets directory can be deleted", function(ctx)
	vim.fn.delete(ctx.assets, "rf")
	local deleted = notes.delete(ctx.note)
	h.equal(true, deleted)
	h.equal(nil, vim.uv.fs_stat(ctx.note))
end)

test("an unsaved note prevents any bundle deletion", function(ctx)
	local buf = vim.fn.bufadd(ctx.note)
	vim.fn.bufload(buf)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Unsaved edits" })
	local deleted = notes.delete(ctx.note)
	h.equal(false, deleted)
	h.equal({ "# A note" }, vim.fn.readfile(ctx.note))
	assert(vim.uv.fs_stat(ctx.assets .. "/overview.png"))
	h.equal(true, vim.bo[buf].modified)
	assert(ctx.notices[1]:find("unsaved edits", 1, true))
end)

test("an unsaved scene prevents any bundle deletion", function(ctx)
	local buf = vim.fn.bufadd(ctx.assets .. "/overview.excalidraw")
	vim.fn.bufload(buf)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Unsaved scene" })
	local deleted = notes.delete(ctx.note)
	h.equal(false, deleted)
	assert(vim.uv.fs_stat(ctx.note))
	h.equal({ "{}" }, vim.fn.readfile(ctx.assets .. "/overview.excalidraw"))
	h.equal(true, vim.bo[buf].modified)
end)

test("deleting saved buffers preserves adjacent windows and focus", function(ctx)
	vim.cmd("vsplit " .. vim.fn.fnameescape(ctx.note))
	local note_buf, note_win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
	local scene_buf = vim.fn.bufadd(ctx.assets .. "/overview.excalidraw")
	vim.fn.bufload(scene_buf)
	vim.api.nvim_set_current_win(ctx.win)
	local width = vim.api.nvim_win_get_width(ctx.win)
	local deleted = notes.delete(ctx.note)
	h.equal(true, deleted)
	h.equal(false, vim.api.nvim_buf_is_valid(note_buf))
	h.equal(false, vim.api.nvim_buf_is_valid(scene_buf))
	h.equal(true, vim.api.nvim_win_is_valid(note_win))
	h.equal(ctx.win, vim.api.nvim_get_current_win())
	h.equal(ctx.buf, vim.api.nvim_win_get_buf(ctx.win))
	h.equal(width, vim.api.nvim_win_get_width(ctx.win))
end)

test("an assets deletion failure retains the Markdown note", function(ctx)
	vim.fn.delete = function(path, flags)
		if path == ctx.assets then
			return -1
		end
		return delete(path, flags)
	end
	local deleted = notes.delete(ctx.note)
	h.equal(false, deleted)
	assert(vim.uv.fs_stat(ctx.note))
	assert(vim.uv.fs_stat(ctx.assets .. "/overview.png"))
	assert(ctx.notices[1]:find("Could not fully delete", 1, true))
end)

test("a note deletion failure reports that the assets were already removed", function(ctx)
	vim.uv.fs_unlink = function(path)
		if path == ctx.note then
			return nil, "EACCES: permission denied: " .. path, "EACCES"
		end
		return unlink(path)
	end
	local deleted = notes.delete(ctx.note)
	h.equal(false, deleted)
	assert(vim.uv.fs_stat(ctx.note))
	h.equal(nil, vim.uv.fs_stat(ctx.assets))
	assert(ctx.notices[1]:find("Assets deleted, but could not delete note", 1, true))
end)

test("deleting an assets symlink preserves the linked directory", function(ctx)
	local shared = ctx.directory .. "/shared"
	assert(vim.uv.fs_rename(ctx.assets, shared))
	assert(vim.uv.fs_symlink(shared, ctx.assets))
	local deleted = notes.delete(ctx.note)
	h.equal(true, deleted)
	h.equal(nil, vim.uv.fs_lstat(ctx.assets))
	assert(vim.uv.fs_stat(shared .. "/overview.png"))
end)

test("fallback deletion refreshes the original picker from disk", function(ctx)
	local remaining = ctx.directory .. "/remaining.md"
	vim.fn.writefile({ "# Keep" }, remaining)
	notes.open()
	ctx.choose(ctx.items[#ctx.items])
	h.equal("Delete note and assets", ctx.options.prompt)
	ctx.choose(ctx.note)
	h.equal("Diagram notes", ctx.options.prompt)
	h.equal(remaining, ctx.items[1])
	h.equal(3, #ctx.items)
	h.equal(nil, vim.uv.fs_stat(ctx.assets))
	h.equal(ctx.win, vim.api.nvim_get_current_win())
end)

test("cancelling fallback deletion preserves the bundle", function(ctx)
	notes.open()
	ctx.choose(ctx.items[#ctx.items])
	ctx.choose(nil)
	assert(vim.uv.fs_stat(ctx.note))
	assert(vim.uv.fs_stat(ctx.assets))
	h.equal(ctx.win, vim.api.nvim_get_current_win())
end)

test("deleting the last fallback note reports an empty directory", function(ctx)
	notes.open()
	ctx.choose(ctx.items[#ctx.items])
	ctx.choose(ctx.note)
	h.equal(nil, vim.uv.fs_stat(ctx.note))
	assert(ctx.notices[1]:find("No diagram notes yet", 1, true))
end)

test("Snacks deletion resolves relative items and refreshes the open picker", function(ctx)
	local options
	package.loaded.snacks = {
		picker = {
			pick = function(opts)
				options = opts
			end,
			util = {
				path = function(item)
					return item.cwd .. "/" .. item.file
				end,
			},
		},
	}
	notes.open()
	local refreshed = false
	local picker = {
		refresh = function()
			refreshed = true
		end,
	}
	options.actions.delete_note(picker, { cwd = ctx.directory, file = "project/note with spaces.md" })
	h.equal(nil, vim.uv.fs_stat(ctx.note))
	h.equal(nil, vim.uv.fs_stat(ctx.assets))
	h.equal(true, refreshed)
end)

test("Snacks deletion with no highlighted item is a no-op", function(ctx)
	local options
	package.loaded.snacks = { picker = {
		pick = function(opts)
			options = opts
		end,
	} }
	notes.open()
	options.actions.delete_note({}, nil)
	assert(vim.uv.fs_stat(ctx.note))
	h.equal({}, ctx.notices)
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

test("fallback export passes the selected note to the PDF exporter", function(ctx)
	local exported
	package.loaded["diagram_notes.export"] = {
		file = function(path)
			exported = path
		end,
	}
	notes.open()
	ctx.choose(ctx.items[#ctx.items - 1])
	h.equal("Export note to PDF", ctx.options.prompt)
	ctx.choose(ctx.note)
	h.equal(ctx.note, exported)
	h.equal("Diagram notes", ctx.options.prompt)
	h.equal(ctx.win, vim.api.nvim_get_current_win())
end)

test("Snacks export resolves the highlighted note without closing the picker", function(ctx)
	local options, exported
	package.loaded["diagram_notes.export"] = {
		file = function(path)
			exported = path
		end,
	}
	package.loaded.snacks = {
		picker = {
			pick = function(opts)
				options = opts
			end,
			util = {
				path = function(item)
					return item.cwd .. "/" .. item.file
				end,
			},
		},
	}
	notes.open()
	options.actions.export_note({}, { cwd = ctx.directory, file = "project/note with spaces.md" })
	h.equal(ctx.note, exported)
	h.equal(ctx.win, vim.api.nvim_get_current_win())
end)

h.finish()
