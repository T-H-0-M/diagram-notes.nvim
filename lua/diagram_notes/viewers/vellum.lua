local M = {}

function M.prepare()
	require("vellum").setup({ auto_open = false, tab = false, split = "right" })
end

function M.open()
	require("vellum").open()
	local buf = vim.fn.bufnr("vellum://preview")
	local win = vim.fn.bufwinid(buf)
	assert(win ~= -1, "Vellum did not open a preview window")
	return buf, win
end

function M.close()
	require("vellum").close()
end

function M.redraw()
	require("vellum").redraw()
end

function M.invalidate(path)
	local image = require("vellum.image")
	image.drop(image.id(path))
	require("vellum.render").reset()
	M.redraw()
end

function M.zoom()
	require("vellum").zoom()
end

function M.problem()
	local image = require("vellum.image")
	return image.problem() or (not image.supported and "Use a Kitty-graphics terminal such as Ghostty or Kitty" or nil)
end

return M
