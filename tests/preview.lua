local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(vim.env.VELLUM_PATH or (root .. "/.deps/vellum.nvim"))
vim.g.mapleader = " "
vim.o.termguicolors = true
vim.o.hidden = true

require("vellum").setup({})
local preview = require("diagram_notes.preview")
require("diagram_notes").setup()
local image = require("vellum.image")
local drop_image = image.drop

local passed, failed = 0, 0
local notify = vim.notify
local system = vim.system
local select = vim.ui.select
local exporter = package.loaded["diagram_notes.export"]
local notices = {}
vim.notify = function(message)
	notices[#notices + 1] = message
end

local function equal(expected, actual)
	assert(vim.deep_equal(expected, actual), "Expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
end

local function rendered()
	local buf = vim.fn.bufnr("vellum://preview")
	return buf ~= -1 and table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") or ""
end

local function test(name, body)
	local directory = vim.fn.tempname()
	vim.fn.mkdir(directory, "p")
	notices = {}
	local ok, err = xpcall(function()
		vim.cmd("enew!")
		local code = vim.api.nvim_get_current_win()
		vim.bo.filetype = "lua"
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local value = 42" })
		local code_buf = vim.api.nvim_get_current_buf()
		local file = directory .. "/diagram.md"
		vim.fn.writefile({ "# Architecture", "", "Original explanation.", "", "More detail." }, file)
		vim.cmd("rightbelow vsplit " .. vim.fn.fnameescape(file))
		vim.api.nvim_win_set_width(code, 47)
		vim.bo.filetype = "markdown"
		vim.wo.number = true
		vim.wo.relativenumber = true
		vim.wo.wrap = true
		vim.wo.scrolloff = 0
		vim.api.nvim_win_set_cursor(0, { 3, 4 })
		body({
			file = file,
			source = vim.api.nvim_get_current_buf(),
			code_win = code,
			code_buf = code_buf,
			code_width = vim.api.nvim_win_get_width(code),
		})
	end, debug.traceback)
	image.drop = drop_image
	preview.close()
	vim.system = system
	vim.ui.select = select
	package.loaded["diagram_notes.export"] = exporter
	require("diagram_notes.config").setup()
	vim.cmd("silent! tabonly!")
	vim.cmd("silent! only!")
	vim.cmd("enew!")
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if buf ~= vim.api.nvim_get_current_buf() then
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
	end
	vim.fn.delete(directory, "rf")
	if ok then
		passed = passed + 1
		print("PASS " .. name)
	else
		failed = failed + 1
		io.stderr:write("FAIL " .. name .. "\n" .. err .. "\n")
	end
end

test("preview replaces the Markdown pane without changing the adjacent code", function(ctx)
	preview.toggle()
	equal("vellum://preview", vim.api.nvim_buf_get_name(0))
	equal(ctx.code_buf, vim.api.nvim_win_get_buf(ctx.code_win))
	equal(ctx.code_width, vim.api.nvim_win_get_width(ctx.code_win))
	equal(1, #vim.api.nvim_list_tabpages())
	assert(rendered():find("Original explanation.", 1, true))
end)

test("returning to source restores its cursor and window options", function(ctx)
	preview.toggle()
	preview.toggle()
	equal(ctx.source, vim.api.nvim_get_current_buf())
	equal({ 3, 4 }, vim.api.nvim_win_get_cursor(0))
	equal({ true, true, true }, { vim.wo.number, vim.wo.relativenumber, vim.wo.wrap })
	equal(ctx.code_width, vim.api.nvim_win_get_width(ctx.code_win))
	equal(2, #vim.api.nvim_list_wins())
end)

test("navigating code leaves the selected diagram visible", function(ctx)
	preview.toggle()
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_set_current_win(ctx.code_win)
	equal("vellum://preview", vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)))
	assert(rendered():find("Original explanation.", 1, true))
end)

test("returning to source keeps a resized preview's width", function(ctx)
	preview.toggle()
	vim.api.nvim_win_set_width(0, 43)
	local width = vim.api.nvim_win_get_width(0)
	preview.close()
	equal(ctx.source, vim.api.nvim_get_current_buf())
	equal(width, vim.api.nvim_win_get_width(0))
end)

test("a single Markdown pane returns to source without leaving a hidden window", function(ctx)
	vim.api.nvim_win_close(ctx.code_win, true)
	preview.toggle()
	preview.close()
	equal(ctx.source, vim.api.nvim_get_current_buf())
	equal(1, #vim.api.nvim_list_wins())
end)

test("an agent's atomic file replacement refreshes the preview", function(ctx)
	preview.toggle()
	vim.api.nvim_set_current_win(ctx.code_win)
	vim.fn.writefile({ "# Architecture", "", "Agent update." }, ctx.file .. ".new")
	assert(vim.uv.fs_rename(ctx.file .. ".new", ctx.file))
	assert(
		vim.wait(3000, function()
			return rendered():find("Agent update.", 1, true) ~= nil
		end),
		"Preview stayed stale"
	)
	equal({ "# Architecture", "", "Agent update." }, vim.api.nvim_buf_get_lines(ctx.source, 0, -1, false))
	equal(ctx.code_win, vim.api.nvim_get_current_win())
end)

test("external edits do not overwrite unsaved Markdown", function(ctx)
	vim.api.nvim_buf_set_lines(ctx.source, 2, 3, false, { "Unsaved local edit." })
	preview.toggle()
	vim.fn.writefile({ "# Agent version" }, ctx.file)
	preview.refresh()
	equal("Unsaved local edit.", vim.api.nvim_buf_get_lines(ctx.source, 2, 3, false)[1])
	equal(true, vim.bo[ctx.source].modified)
	assert(table.concat(notices, "\n"):find("Unsaved source edits were preserved", 1, true))
end)

test("asset-only changes invalidate Vellum's image cache while Markdown has unsaved edits", function(ctx)
	local directory = vim.fs.dirname(vim.api.nvim_buf_get_name(ctx.source)) .. "/assets"
	vim.fn.mkdir(directory, "p")
	local path = directory .. "/drawing.png"
	local png = vim.base64.decode(
		"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII="
	)
	local file = assert(io.open(path, "wb"))
	file:write(png)
	file:close()
	vim.api.nvim_buf_set_lines(ctx.source, 2, -1, false, { "Unsaved context.", "", "![Drawing](assets/drawing.png)" })
	preview.toggle()
	local invalidated = false
	image.drop = function(id)
		if id == image.id(path) then
			invalidated = true
		end
		drop_image(id)
	end
	vim.api.nvim_set_current_win(ctx.code_win)
	file = assert(io.open(path .. ".new", "wb"))
	file:write(png .. "updated")
	file:close()
	assert(vim.uv.fs_rename(path .. ".new", path))
	assert(
		vim.wait(3000, function()
			return invalidated
		end),
		"Vellum kept the cached image"
	)
	equal(true, vim.bo[ctx.source].modified)
	equal("Unsaved context.", vim.api.nvim_buf_get_lines(ctx.source, 2, 3, false)[1])
	equal(ctx.code_win, vim.api.nvim_get_current_win())
end)

test("entering another Markdown file restores the old source without taking focus", function(ctx)
	preview.toggle()
	vim.api.nvim_set_current_win(ctx.code_win)
	vim.cmd("enew")
	vim.bo.filetype = "markdown"
	local other = vim.api.nvim_get_current_buf()
	vim.api.nvim_exec_autocmds("BufEnter", { buffer = other })
	equal(other, vim.api.nvim_get_current_buf())
	equal(2, #vim.api.nvim_list_wins())
	assert(vim.fn.bufwinid(ctx.source) ~= -1)
end)

test("closing the preview window cleans up its hidden source window", function(ctx)
	preview.toggle()
	vim.api.nvim_win_close(0, true)
	assert(
		vim.wait(1000, function()
			return #vim.api.nvim_list_wins() == 1
		end),
		"Hidden window leaked"
	)
	equal(ctx.code_buf, vim.api.nvim_get_current_buf())
	equal(true, vim.api.nvim_buf_is_valid(ctx.source))
end)

test("a closed preview cannot refresh a later document", function(ctx)
	preview.toggle()
	vim.fn.writefile({ "# Late update" }, ctx.file)
	preview.close()
	vim.cmd("enew")
	vim.bo.filetype = "markdown"
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# Second document" })
	preview.toggle()
	vim.api.nvim_exec_autocmds("FocusGained", {})
	assert(vim.wait(1000, function()
		return rendered():find("Second document", 1, true) ~= nil
	end))
	assert(not rendered():find("Late update", 1, true))
end)

test("reconfiguring an active preview restores the source and releases its window", function(ctx)
	preview.toggle()
	require("diagram_notes").setup({ render = { theme = "light" } })
	equal(ctx.source, vim.api.nvim_get_current_buf())
	equal(ctx.code_width, vim.api.nvim_win_get_width(ctx.code_win))
	equal(2, #vim.api.nvim_list_wins())
end)

test("deleting a previewed note cancels exports and releases its hidden window", function(ctx)
	local assets = vim.fs.dirname(ctx.file) .. "/diagram.assets"
	vim.fn.mkdir(assets, "p")
	vim.fn.writefile({ '{"elements":[]}' }, assets .. "/overview.excalidraw")
	vim.fn.writefile({ "![Drawing](diagram.assets/overview.png)" }, ctx.file)
	vim.cmd("edit!")
	local killed, finish
	vim.system = function(_, _, callback)
		finish = callback
		return {
			kill = function()
				killed = true
			end,
		}
	end
	preview.toggle()
	vim.api.nvim_set_current_win(ctx.code_win)
	local deleted = require("diagram_notes.notes").delete(ctx.file)
	equal(true, deleted)
	equal(true, killed)
	equal(false, vim.api.nvim_buf_is_valid(ctx.source))
	equal(2, #vim.api.nvim_list_wins())
	equal(ctx.code_win, vim.api.nvim_get_current_win())
	equal(ctx.code_buf, vim.api.nvim_win_get_buf(ctx.code_win))
	equal(ctx.code_width, vim.api.nvim_win_get_width(ctx.code_win))
	finish({ code = 143, stderr = "terminated" })
	local settled = false
	vim.schedule(function()
		settled = true
	end)
	assert(vim.wait(1000, function()
		return settled
	end))
	equal(nil, vim.uv.fs_stat(assets))
	equal({}, notices)
end)

test("deleting another note keeps the current preview active", function(ctx)
	local other = vim.fs.dirname(ctx.file) .. "/other.md"
	vim.fn.writefile({ "# Other" }, other)
	preview.toggle()
	local win = vim.api.nvim_get_current_win()
	local deleted = require("diagram_notes.notes").delete(other)
	equal(true, deleted)
	equal(true, vim.api.nvim_win_is_valid(win))
	equal("vellum://preview", vim.api.nvim_buf_get_name(0))
	assert(rendered():find("Original explanation.", 1, true))
end)

test("the fallback picker can open another note after deleting its launching preview", function(ctx)
	local directory = assert(vim.uv.fs_realpath(vim.fs.dirname(ctx.file)))
	local other = directory .. "/other.md"
	vim.fn.writefile({ "# Other" }, other)
	require("diagram_notes.config").setup({ notes_dir = directory, picker = "select" })
	local items, choose
	vim.ui.select = function(list, _, callback)
		items, choose = list, callback
	end
	preview.toggle()
	require("diagram_notes.notes").open()
	choose(items[#items])
	choose(assert(vim.uv.fs_realpath(ctx.file)))
	choose(other)
	equal(other, vim.api.nvim_buf_get_name(0))
	equal(ctx.code_buf, vim.api.nvim_win_get_buf(ctx.code_win))
end)

test("the PDF command exports the source buffer to a custom path with spaces", function(ctx)
	local selected, output
	package.loaded["diagram_notes.export"] = {
		buffer = function(buf, path)
			selected, output = buf, path
		end,
	}
	local path = vim.fs.dirname(ctx.file) .. "/shared note.pdf"
	vim.cmd("DiagramExport " .. vim.fn.fnameescape(path))
	equal(ctx.source, selected)
	equal(path, output)
end)

test("the export leader mapping resolves the hidden source while previewing", function(ctx)
	local selected
	package.loaded["diagram_notes.export"] = {
		buffer = function(buf)
			selected = buf
		end,
	}
	preview.toggle()
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_feedkeys(vim.keycode("<Space>ex"), "x", false)
	equal(ctx.source, selected)
	equal(win, vim.api.nvim_get_current_win())
	equal("vellum://preview", vim.api.nvim_buf_get_name(0))
end)

vim.notify = notify
print(("%d passed, %d failed"):format(passed, failed))
vim.cmd(failed == 0 and "qa!" or "cquit 1")
