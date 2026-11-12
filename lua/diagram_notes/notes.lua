local M = {}

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
			})
		elseif options.picker == "snacks" then
			return vim.notify("Install snacks.nvim or set picker = 'select'", vim.log.levels.ERROR)
		end
	end
	local files = vim.fs.find(function(name)
		return name:match("%.md$") ~= nil
	end, { path = directory, type = "file", limit = math.huge })
	table.sort(files)
	if #files == 0 then
		return vim.notify("No diagram notes yet in " .. directory, vim.log.levels.INFO)
	end
	local win = vim.api.nvim_get_current_win()
	vim.ui.select(files, {
		prompt = "Diagram notes",
		format_item = function(path)
			return vim.fs.relpath(directory, path) or path
		end,
	}, function(path)
		if path and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_set_current_win(win)
			vim.cmd("vsplit " .. vim.fn.fnameescape(path))
		end
	end)
end

return M
