local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(vim.env.VELLUM_PATH or (root .. "/.deps/vellum.nvim"))
local api, uv = vim.api, vim.uv
local job
local function read(path)
	local file = assert(io.open(path, "rb"))
	local text = file:read("*a")
	file:close()
	return text
end

local ok, err = xpcall(function()
	vim.fn.mkdir(root .. "/.deps", "p")
	local directory = assert(uv.fs_mkdtemp(root .. "/.deps/pdf-XXXXXX"))
	local assets = directory .. "/note assets"
	vim.fn.mkdir(assets, "p")
	local scene, image = assets .. "/overview.excalidraw", assets .. "/overview.png"
	vim.fn.writefile(vim.fn.readfile(root .. "/tests/fixtures/overview.excalidraw"), scene)
	local renderer = require("diagram_notes.excalidraw")
	local options = require("diagram_notes.config").get().render
	local rendered, render_error
	assert(renderer.render(renderer.prepare(scene, options), image, options, function(failure)
		rendered, render_error = true, failure
	end))
	assert(
		vim.wait(120000, function()
			return rendered
		end, 20),
		"Dark preview render timed out"
	)
	assert(not render_error, render_error)
	local original_scene, original_image = read(scene), read(image)
	local lines = {
		"# Diagram notes PDF export",
		"",
		"This note combines **conversation context**, a diagram, a table, and *code*.",
		"",
		"## Architecture",
		"",
		"![Overview](<note assets/overview.png>)",
		"",
		"[Drawing source](<note assets/overview.excalidraw>)",
		"",
		"The diagram uses dark outlines and labels on a white page.",
		"",
		"| Step | Result |",
		"| --- | --- |",
		"| Snapshot | Keep current editor context |",
		"| Render | Prepare printable diagram images |",
		"| Export | Publish a self-contained PDF |",
		"",
		"```lua",
		'require("diagram_notes").export("note.pdf")',
		"```",
		"",
		"## Decisions",
	}
	for i = 1, 28 do
		lines[#lines + 1] = ("- Decision %d: keep the explanation and diagram together when sharing the note."):format(
			i
		)
	end
	local note = directory .. "/note.md"
	vim.fn.writefile(lines, note)
	local buf = api.nvim_create_buf(true, false)
	api.nvim_buf_set_name(buf, note)
	vim.bo[buf].filetype = "markdown"
	lines[#lines + 1] = ""
	lines[#lines + 1] = "Unsaved editor context is included in this PDF."
	api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	local completed, failure
	local output = directory .. "/note.pdf"
	job = require("diagram_notes.export").buffer(buf, output, function(problem)
		completed, failure = true, problem
	end)
	assert(
		vim.wait(120000, function()
			return completed
		end, 20),
		"PDF export timed out"
	)
	assert(not failure, failure)
	assert(read(output):sub(1, 5) == "%PDF-" and #read(output) > 4000, "Invalid or empty PDF")
	assert(read(scene) == original_scene and read(image) == original_image, "Source assets changed")
	assert(vim.bo[buf].modified, "Export saved the source buffer")
	assert(#vim.fn.glob(directory .. "/.diagram-export-*", false, true) == 0, "Export workspace leaked")
	vim.fn.writefile({ output }, root .. "/.deps/pdf-result.txt")
	print("PASS real PDF export with printable diagrams and unsaved context: " .. output)
end, debug.traceback)

if job then
	job:cancel()
end
if not ok then
	io.stderr:write(err .. "\n")
end
vim.cmd(ok and "qa!" or "cquit 1")
