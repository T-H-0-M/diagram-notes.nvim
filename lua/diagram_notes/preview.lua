local M = {}
local api, uv = vim.api, vim.uv
local viewer = require("diagram_notes.viewers.vellum")
local active

local function signature(file)
	local stat = uv.fs_stat(file)
	return stat and { stat.ino, stat.size, stat.mtime, stat.ctime }
end

local function window_options(win)
	local options = {}
	for name, info in pairs(api.nvim_get_all_options_info()) do
		if info.scope == "win" then
			options[name] = api.nvim_get_option_value(name, { win = win })
		end
	end
	return options
end

local function markdown(buf)
	return vim.bo[buf].buftype == "" and vim.tbl_contains({ "markdown", "mdx" }, vim.bo[buf].filetype)
end

local function notify(message)
	vim.notify(message, vim.log.levels.WARN, { title = "Markdown preview" })
end

local function with_layout(fn)
	local equalalways = vim.o.equalalways
	vim.o.equalalways = false
	local ok, err = xpcall(fn, debug.traceback)
	local layout = vim.fn.winrestcmd()
	-- Re-enabling equalalways rebalances every split.
	vim.o.equalalways = equalalways
	if not ok then
		error(err)
	end
	vim.cmd(layout)
end

local function restore_window(win, s)
	for name, value in pairs(s.options) do
		pcall(api.nvim_set_option_value, name, value, { win = win })
	end
	api.nvim_win_call(win, function()
		vim.fn.winrestview(s.view)
	end)
end

function M.close()
	local s = active
	if not s then
		return
	end
	active = nil
	api.nvim_del_augroup_by_id(s.group)
	if s.assets then
		s.assets:close()
	end
	for _, handle in ipairs({ s.timer, s.watcher }) do
		if handle and not handle:is_closing() then
			handle:stop()
			handle:close()
		end
	end

	local focused = api.nvim_get_current_win()
	with_layout(function()
		local restored, layout
		if s.preview_win and api.nvim_win_is_valid(s.preview_win) and api.nvim_buf_is_valid(s.source) then
			layout = api.nvim_win_call(s.preview_win, vim.fn.winrestcmd)
			restored = api.nvim_open_win(s.source, false, { split = "left", win = s.preview_win })
			restore_window(restored, s)
		end
		viewer.close()
		if s.holder and api.nvim_win_is_valid(s.holder) then
			api.nvim_win_close(s.holder, true)
		end
		if api.nvim_buf_is_valid(s.source) then
			vim.bo[s.source].autoread = s.autoread
		end
		if restored then
			api.nvim_win_call(restored, function()
				vim.cmd(layout)
			end)
			if focused == s.preview_win or not api.nvim_win_is_valid(focused) then
				api.nvim_set_current_win(restored)
			end
		end
	end)
end

function M.close_for(buf)
	if active and active.source == buf then
		M.close()
	end
end

function M.refresh(force)
	local s = active
	if not s or s.busy or not api.nvim_buf_is_valid(s.source) then
		return
	end
	if vim.bo[s.source].modified then
		if not s.conflict then
			if s.file ~= "" and not vim.deep_equal(signature(s.file), s.signature) then
				notify(
					"The Markdown file changed on disk. Unsaved source edits were preserved; return to source to resolve them."
				)
				s.conflict = true
			end
		end
	else
		s.conflict = false
		s.busy = true
		local ok, err = pcall(vim.cmd, "checktime " .. s.source)
		s.busy = false
		if not ok then
			notify(tostring(err))
			return
		end
		s.signature = signature(s.file)
	end
	if s.assets then
		s.assets:refresh(force == true)
	end
	viewer.redraw()
end

local function watch(s)
	local function schedule()
		if active ~= s or s.timer:is_closing() then
			return
		end
		s.timer:start(
			require("diagram_notes.config").get().debounce_ms,
			0,
			vim.schedule_wrap(function()
				if active == s then
					M.refresh()
				end
			end)
		)
	end

	s.timer = assert(uv.new_timer())
	if s.file ~= "" then
		-- Watch the directory because agents commonly replace the file by renaming.
		s.watcher = assert(uv.new_fs_event())
		local ok, err = s.watcher:start(vim.fs.dirname(s.file), {}, function(watch_err, filename)
			if not watch_err and (not filename or filename == vim.fs.basename(s.file)) then
				schedule()
			end
		end)
		if not ok then
			notify("Could not watch Markdown file: " .. tostring(err))
			s.watcher:close()
		end
	end
	api.nvim_create_autocmd({ "FocusGained", "BufEnter", "InsertLeave" }, {
		group = s.group,
		callback = schedule,
	})
	api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "FileChangedShellPost", "TextChanged", "TextChangedI" }, {
		group = s.group,
		buffer = s.source,
		callback = schedule,
	})
	api.nvim_create_autocmd("WinClosed", {
		group = s.group,
		pattern = { tostring(s.preview_win), tostring(s.holder) },
		callback = function()
			vim.schedule(function()
				if active == s then
					M.close()
				end
			end)
		end,
	})
	api.nvim_create_autocmd("BufWipeout", {
		group = s.group,
		buffer = s.source,
		callback = function()
			vim.schedule(function()
				if active == s then
					M.close()
				end
			end)
		end,
	})
end

function M.toggle()
	local current = api.nvim_get_current_buf()
	if active and (current == active.preview_buf or current == active.source) then
		return M.close()
	end
	if not markdown(current) then
		return notify("Open a Markdown file to preview it.")
	end
	local ready, problem = pcall(viewer.prepare)
	if not ready then
		return notify("Vellum is unavailable: " .. tostring(problem))
	end
	M.close()
	viewer.close()
	local source_win = api.nvim_get_current_win()
	local layout = vim.fn.winrestcmd()
	local s = {
		source = current,
		view = vim.fn.winsaveview(),
		options = window_options(source_win),
		autoread = vim.bo[current].autoread,
		file = api.nvim_buf_get_name(current),
		group = api.nvim_create_augroup("DiagramNotesPreviewActive", { clear = true }),
		busy = true,
	}
	s.signature = signature(s.file)
	active = s
	local ok, err = xpcall(function()
		with_layout(function()
			-- Vellum needs a source window even when only the preview is visible.
			s.holder = api.nvim_open_win(current, false, {
				relative = "editor",
				row = 0,
				col = 0,
				width = 1,
				height = 1,
				hide = true,
				focusable = false,
				noautocmd = true,
			})
			vim.bo[current].autoread = true
			s.preview_buf, s.preview_win = viewer.open()
			api.nvim_set_current_win(s.preview_win)
			api.nvim_win_close(source_win, true)
			vim.cmd(layout)
		end)
		vim.keymap.set("n", "q", M.close, { buffer = s.preview_buf, desc = "Markdown source" })
		s.busy = false
		watch(s)
		s.assets = require("diagram_notes.excalidraw").watch(s.source, function(path)
			if active ~= s or not api.nvim_win_is_valid(s.preview_win) then
				return
			end
			local view = api.nvim_win_call(s.preview_win, vim.fn.winsaveview)
			viewer.invalidate(path)
			api.nvim_win_call(s.preview_win, function()
				vim.fn.winrestview(view)
			end)
		end)
		viewer.redraw()
	end, debug.traceback)
	if not ok then
		M.close()
		notify(err)
	end
end

function M.render()
	if not active then
		M.toggle()
	end
	M.refresh(true)
end

function M.zoom()
	if not active then
		M.toggle()
	end
	if active and api.nvim_win_is_valid(active.preview_win) then
		api.nvim_set_current_win(active.preview_win)
		viewer.zoom()
	end
end

function M.setup()
	local group = api.nvim_create_augroup("DiagramNotesPreview", { clear = true })
	-- End this preview before Vellum's BufEnter handler can follow another document.
	api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function(ev)
			if active and not active.busy and ev.buf ~= active.source and markdown(ev.buf) then
				M.close()
			end
		end,
	})
	api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.close })
end

return M
