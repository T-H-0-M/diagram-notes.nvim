local M = {}
local api, uv = vim.api, vim.uv

local function warn(message)
	vim.notify(message, vim.log.levels.WARN, { title = "Diagram notes" })
end

local function resolved(path)
	local directory = vim.fs.dirname(path)
	return uv.fs_realpath(path) or vim.fs.joinpath(uv.fs_realpath(directory) or directory, vim.fs.basename(path))
end

local function bundle_buffers(path, assets)
	local buffers = {}
	path, assets = resolved(path), resolved(assets)
	for _, buf in ipairs(api.nvim_list_bufs()) do
		local name = api.nvim_buf_get_name(buf)
		if name ~= "" then
			name = resolved(name)
			if name == path or name:sub(1, #assets + 1) == assets .. "/" then
				buffers[#buffers + 1] = buf
			end
		end
	end
	return buffers
end

local function clean_buffers(buffers)
	for _, buf in ipairs(buffers) do
		if api.nvim_buf_is_valid(buf) then
			local _, _, code = uv.fs_stat(api.nvim_buf_get_name(buf))
			if code == "ENOENT" and not vim.bo[buf].modified then
				local ok, err = pcall(function()
					local replacement
					for _, win in ipairs(vim.fn.win_findbuf(buf)) do
						replacement = replacement or api.nvim_create_buf(true, false)
						local fixed = vim.wo[win].winfixbuf
						vim.wo[win].winfixbuf = false
						local changed, problem = pcall(api.nvim_win_set_buf, win, replacement)
						vim.wo[win].winfixbuf = fixed
						if not changed then
							error(problem)
						end
					end
					api.nvim_buf_delete(buf, {})
				end)
				if not ok then
					warn("Files deleted, but could not close buffer: " .. tostring(err))
				end
			end
		end
	end
end

function M.delete(path)
	path = vim.fs.normalize(vim.fs.abspath(path))
	if not path:match("%.md$") then
		warn("Not a Markdown note: " .. path)
		return false
	end
	local assets = path:gsub("%.md$", ".assets")
	local buffers = bundle_buffers(path, assets)
	for _, buf in ipairs(buffers) do
		if vim.bo[buf].modified then
			warn("Save or discard unsaved edits before deleting: " .. api.nvim_buf_get_name(buf))
			return false
		end
	end
	for _, buf in ipairs(buffers) do
		require("diagram_notes.preview").close_for(buf)
	end

	local stat, err, code = uv.fs_lstat(assets)
	if not stat and code ~= "ENOENT" then
		warn("Could not inspect assets: " .. tostring(err))
		return false
	end
	if stat then
		if stat.type ~= "directory" and stat.type ~= "link" then
			warn("Expected an assets directory: " .. assets)
			return false
		end
		local ok, result = pcall(vim.fn.delete, assets, stat.type == "directory" and "rf" or "")
		if not ok or result ~= 0 then
			clean_buffers(buffers)
			warn("Could not fully delete " .. assets .. "; Markdown note retained")
			return false
		end
	end
	local deleted
	deleted, err, code = uv.fs_unlink(path)
	clean_buffers(buffers)
	if not deleted and code ~= "ENOENT" then
		warn((stat and "Assets deleted, but could not delete note: " or "Could not delete note: ") .. tostring(err))
		return false
	end
	return true
end

local function select_note(directory, win, deleting)
	local files = vim.fs.find(function(name)
		return name:match("%.md$") ~= nil
	end, { path = directory, type = "file", limit = math.huge })
	table.sort(files)
	if #files == 0 then
		return vim.notify("No diagram notes yet in " .. directory, vim.log.levels.INFO)
	end
	local delete_action = {}
	if not deleting then
		files[#files + 1] = delete_action
	end
	vim.ui.select(files, {
		prompt = deleting and "Delete note and assets" or "Diagram notes",
		format_item = function(path)
			return path == delete_action and "Delete note…" or (vim.fs.relpath(directory, path) or path)
		end,
	}, function(path)
		if path == delete_action then
			select_note(directory, win, true)
		elseif path and deleting then
			M.delete(path)
			if not api.nvim_win_is_valid(win) then
				win = api.nvim_get_current_win()
			end
			select_note(directory, win, false)
		elseif path and api.nvim_win_is_valid(win) then
			api.nvim_set_current_win(win)
			vim.cmd("vsplit " .. vim.fn.fnameescape(path))
		end
	end)
end

function M.open()
	local options = require("diagram_notes.config").get()
	local directory = options.notes_dir
	if vim.fn.isdirectory(directory) == 0 then
		return vim.notify("No diagram notes yet in " .. directory, vim.log.levels.INFO)
	end
	if options.picker ~= "select" then
		local ok, snacks = pcall(require, "snacks")
		if ok and snacks.picker then
			return snacks.picker.pick({
				title = "Diagram notes",
				finder = "files",
				format = "file",
				preview = "file",
				cwd = directory,
				ft = "md",
				hidden = true,
				ignored = true,
				show_empty = true,
				layout = { preview = true },
				confirm = { action = "jump", cmd = "vsplit" },
				actions = {
					delete_note = function(picker, item)
						if item then
							M.delete(snacks.picker.util.path(item))
							picker:refresh()
						end
					end,
				},
				win = {
					input = {
						keys = { ["<C-x>"] = { "delete_note", mode = { "n", "i" }, desc = "Delete note and assets" } },
					},
					list = { keys = { ["<C-x>"] = { "delete_note", desc = "Delete note and assets" } } },
				},
			})
		elseif options.picker == "snacks" then
			return vim.notify("Install snacks.nvim or set picker = 'select'", vim.log.levels.ERROR)
		end
	end
	select_note(directory, api.nvim_get_current_win(), false)
end

return M
