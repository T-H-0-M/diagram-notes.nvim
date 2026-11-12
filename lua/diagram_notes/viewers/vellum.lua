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

function M.export_problem()
	local module = vim.api.nvim_get_runtime_file("lua/vellum/browser.lua", false)[1]
	if not module then
		return "Install vellum.nvim for PDF export"
	end
	if vim.fn.executable("node") == 0 then
		return "PDF export requires Node.js and :Vellum build"
	end
	local root = vim.fn.fnamemodify(module, ":h:h:h")
	if not vim.uv.fs_stat(root .. "/render/node_modules") then
		return "PDF export requires Vellum's browser renderer; run :Vellum build"
	end
end

function M.export(markdown, directory, output, done)
	local kinds = {}
	for kind, attributes in pairs(require("vellum.render").alerts) do
		kinds[kind:lower()] = attributes[2]:lower()
	end
	markdown = [[<style>
body {
  font-family: "Source Serif 4", Georgia, serif;
  font-weight: 400;
}
code, pre {
  font-family: "JetBrainsMono Nerd Font Mono", "JetBrains Mono", monospace;
  font-weight: 500;
}
@media print {
  h1, h2, h3, h4, h5, h6 { break-after: avoid; }
  img { max-height: 240mm; width: auto; height: auto; }
}
</style>

]] .. markdown
	require("vellum.browser").export({ markdown = markdown, dir = directory, out = output, kinds = kinds }, done)
end

function M.problem()
	local image = require("vellum.image")
	return image.problem() or (not image.supported and "Use a Kitty-graphics terminal such as Ghostty or Kitty" or nil)
end

return M
