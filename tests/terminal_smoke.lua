local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(vim.env.VELLUM_PATH or (root .. "/.deps/vellum.nvim"))
if vim.env.SNACKS_PATH then
	vim.opt.runtimepath:prepend(vim.env.SNACKS_PATH)
end
vim.o.termguicolors, vim.o.hidden = true, true
local api = vim.api
local results = {}
local homedir = vim.uv.os_homedir
local function pass(message)
	results[#results + 1] = "PASS " .. message
end
local function read(path)
	local file = assert(io.open(path, "rb"))
	local data = file:read("*a")
	file:close()
	return data
end
local function map(key)
	local mapping = vim.fn.maparg(key, "n", false, true)
	assert(type(mapping.callback) == "function", "Missing viewer key " .. key)
	mapping.callback()
end

vim.defer_fn(function()
	local plugin = require("diagram_notes")
	local ok, err = xpcall(function()
		vim.fn.mkdir(root .. "/.deps", "p")
		local directory = assert(vim.uv.fs_mkdtemp(root .. "/.deps/terminal-XXXXXX"))
		local assets = directory .. "/note.assets"
		vim.fn.mkdir(assets, "p")
		local scene, output, note = assets .. "/overview.excalidraw", assets .. "/overview.png", directory .. "/note.md"
		vim.fn.writefile(vim.fn.readfile(root .. "/tests/fixtures/overview.excalidraw"), scene)
		vim.fn.writefile({
			"# Diagram",
			"",
			"Conversation context.",
			"",
			"![Diagram](note.assets/overview.png)",
			"",
			"[Source](note.assets/overview.excalidraw)",
		}, note)
		plugin.setup({ notes_dir = directory })
		vim.cmd.enew()
		vim.bo.filetype = "lua"
		api.nvim_buf_set_lines(0, 0, -1, false, { "local application_code = 42" })
		local code_win, code_buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
		if vim.env.SNACKS_PATH then
			local snacks = require("snacks")
			snacks.setup({ picker = { enabled = true } })
			vim.cmd.DiagramNotes()
			assert(
				vim.wait(5000, function()
					return snacks.picker.get()[1] ~= nil
				end, 20),
				"Picker did not open"
			)
			local picker = snacks.picker.get()[1]
			assert(
				vim.wait(5000, function()
					return picker:current() ~= nil
				end, 20),
				"Note was not discovered"
			)
			assert(
				vim.wait(5000, function()
					local buf = picker.preview.win.buf
					return buf
						and api.nvim_buf_is_valid(buf)
						and table
							.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
							:find("Conversation context", 1, true)
				end, 20),
				"Picker file preview was empty"
			)
			picker:action("confirm")
			assert(
				vim.wait(3000, function()
					return api.nvim_buf_get_name(0) == note
				end, 20),
				"Selection did not open the note"
			)
			pass("Snacks discovery, file preview, and split selection")
		else
			vim.cmd("vsplit " .. vim.fn.fnameescape(note))
		end
		vim.bo.filetype = "markdown"
		local source = api.nvim_get_current_buf()
		api.nvim_buf_set_lines(source, 2, 3, false, { "Unsaved context." })
		api.nvim_win_set_width(code_win, 73)
		local code_width = api.nvim_win_get_width(code_win)
		vim.cmd.DiagramPreview()
		local preview_win, preview_buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
		assert(api.nvim_buf_get_name(preview_buf) == "vellum://preview")
		local image = require("vellum.image")
		assert(image.supported and not image.problem(), image.problem() or "Unsupported graphics terminal")
		local row
		assert(
			vim.wait(120000, function()
				for i, line in ipairs(api.nvim_buf_get_lines(preview_buf, 0, -1, false)) do
					if line:find(image.placeholder, 1, true) then
						row = i
						return true
					end
				end
			end, 50),
			"Image did not render"
		)
		assert(read(output):sub(1, 8) == "\137PNG\r\n\26\n")
		assert(api.nvim_win_get_width(code_win) == code_width)
		pass("Real CLI export and inline terminal display")
		vim.uv.os_homedir = function()
			return directory
		end
		api.nvim_feedkeys(vim.keycode((vim.g.mapleader or "\\") .. "ex"), "x", false)
		vim.uv.os_homedir = homedir
		local pdf = directory .. "/Downloads/note.pdf"
		assert(
			vim.wait(120000, function()
				return vim.uv.fs_stat(pdf) ~= nil
			end, 20),
			"Leader export did not publish a PDF in Downloads"
		)
		assert(read(pdf):sub(1, 5) == "%PDF-")
		assert(api.nvim_get_current_win() == preview_win and api.nvim_win_get_width(code_win) == code_width)
		pass("Leader PDF export from the preview defaults to Downloads and preserves focus")
		api.nvim_win_set_cursor(preview_win, { row, 0 })
		vim.cmd.DiagramZoom()
		assert(api.nvim_win_get_config(0).relative == "editor")
		map("+")
		assert(vim.wo.winbar:find("125", 1, true))
		local before = api.nvim_buf_get_lines(0, 0, -1, false)
		map("l")
		assert(not vim.deep_equal(before, api.nvim_buf_get_lines(0, 0, -1, false)))
		map("0")
		assert(vim.wo.winbar:find("100", 1, true))
		map("q")
		pass("Full-screen zoom, pan, fit, and close")
		api.nvim_set_current_win(code_win)
		local previous = vim.fn.sha256(read(output))
		local drawing = vim.json.decode(read(scene))
		drawing.elements[1].strokeColor = "#d12a2a"
		vim.fn.writefile({ vim.json.encode(drawing) }, scene .. ".new")
		assert(vim.uv.fs_rename(scene .. ".new", scene))
		assert(
			vim.wait(120000, function()
				return vim.fn.sha256(read(output)) ~= previous
			end, 50),
			"Agent edit did not refresh"
		)
		assert(api.nvim_get_current_win() == code_win and api.nvim_win_get_buf(code_win) == code_buf)
		assert(vim.bo[source].modified and api.nvim_buf_get_lines(source, 2, 3, false)[1] == "Unsaved context.")
		api.nvim_set_current_win(preview_win)
		map("q")
		assert(api.nvim_get_current_buf() == source and api.nvim_win_get_width(code_win) == code_width)
		pass("Live agent update and source restoration preserve editing state")
		if vim.env.SNACKS_PATH then
			vim.cmd.write()
			local remaining = directory .. "/remaining.md"
			vim.fn.writefile({ "# Remaining" }, remaining)
			plugin.toggle()
			plugin.notes()
			local snacks = require("snacks")
			assert(
				vim.wait(5000, function()
					return snacks.picker.get()[1] ~= nil
				end, 20),
				"Picker did not reopen"
			)
			local picker = assert(snacks.picker.get()[1], "Picker did not reopen")
			picker.input:set("note")
			picker:find({ refresh = false })
			assert(
				vim.wait(5000, function()
					return snacks.picker.util.path(picker:current()) == note
				end, 20),
				"Note was not selected for deletion"
			)
			local focused = api.nvim_get_current_win()
			local previous_pdf = assert(vim.uv.fs_stat(pdf)).ino
			vim.uv.os_homedir = function()
				return directory
			end
			local export_binding = api.nvim_win_call(picker.input.win.win, function()
				return vim.fn.maparg("e", "n", false, true)
			end)
			assert(type(export_binding.callback) == "function", "Missing PDF export key")
			export_binding.callback()
			vim.uv.os_homedir = homedir
			assert(
				vim.wait(120000, function()
					return vim.uv.fs_stat(pdf).ino ~= previous_pdf
				end, 20),
				"Picker export did not replace the PDF"
			)
			assert(api.nvim_get_current_win() == focused and picker.input:get() == "note")
			pass("Snacks e exports the highlighted note while preserving picker query and focus")
			local binding = api.nvim_win_call(picker.input.win.win, function()
				assert(vim.tbl_isempty(vim.fn.maparg("d", "i", false, true)), "Deletion overrides search input")
				return vim.fn.maparg("d", "n", false, true)
			end)
			assert(type(binding.callback) == "function", "Missing deletion key")
			binding.callback()
			assert(
				vim.wait(5000, function()
					return picker:count() == 1 and picker:current() == nil
				end, 20),
				"Deleted note stayed in the picker"
			)
			assert(not picker.closed and picker.input:get() == "note", "Deletion reset the picker query")
			assert(api.nvim_get_current_win() == focused, "Deletion took picker focus")
			assert(not vim.uv.fs_stat(note) and not vim.uv.fs_stat(assets), "Note bundle survived deletion")
			assert(not api.nvim_buf_is_valid(source), "Deleted note buffer survived")
			assert(api.nvim_win_get_buf(code_win) == code_buf and api.nvim_win_get_width(code_win) == code_width)
			picker.input:set("")
			picker:find({ refresh = false })
			assert(
				vim.wait(5000, function()
					return snacks.picker.util.path(picker:current()) == remaining
				end, 20),
				"Remaining note was not selected"
			)
			picker:action("confirm")
			assert(
				vim.wait(3000, function()
					return api.nvim_buf_get_name(0) == remaining
				end, 20),
				"Picker could not open a note after deletion"
			)
			pass("Snacks deletion closes the active preview, removes its bundle, and preserves picker query and focus")
		end
	end, debug.traceback)
	if not ok then
		results[#results + 1] = "FAIL " .. err
	end
	vim.uv.os_homedir = homedir
	plugin.close()
	vim.fn.writefile(results, root .. "/.deps/terminal-result.txt")
	if vim.env.DIAGRAM_NOTES_SMOKE_SIGNAL then
		vim.system({ "tmux", "wait-for", "-S", vim.env.DIAGRAM_NOTES_SMOKE_SIGNAL }):wait()
	end
	vim.cmd(ok and "qa!" or "cquit 1")
end, 500)
