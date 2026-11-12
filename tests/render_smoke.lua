local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
local session
local notices = {}
vim.notify = function(message)
	notices[#notices + 1] = message
end
local ok, err = xpcall(function()
	local directory = root .. "/.deps/render-smoke"
	vim.fn.mkdir(directory, "p")
	local scene, output = directory .. "/overview.excalidraw", directory .. "/overview.png"
	local original = vim.fn.readfile(root .. "/tests/fixtures/overview.excalidraw")
	vim.fn.writefile(original, scene)
	vim.fn.delete(output)
	local buf = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(buf, directory .. "/note.md")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "![Diagram](overview.png)" })
	session = require("diagram_notes.excalidraw").watch(buf, function() end)
	assert(
		vim.wait(120000, function()
			return vim.uv.fs_stat(output) ~= nil or #notices > 0
		end, 50),
		"Renderer timed out"
	)
	assert(#notices == 0, table.concat(notices, "\n"))
	assert(vim.deep_equal(original, vim.fn.readfile(scene)), "Editable scene was modified")
	print("PASS real CLI export preserves the editable scene: " .. output)
end, debug.traceback)
if session then
	session:close()
end
if not ok then
	io.stderr:write(err .. "\n")
end
vim.cmd(ok and "qa!" or "cquit 1")
