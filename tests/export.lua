local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
local h = dofile(root .. "/tests/helpers.lua")
local api, uv = vim.api, vim.uv
local export = require("diagram_notes.export")
local renderer = require("diagram_notes.excalidraw")
local viewer = require("diagram_notes.viewers.vellum")
local original = {
	render = renderer.render,
	export = viewer.export,
	problem = viewer.export_problem,
	home = uv.os_homedir,
	notify = vim.notify,
	timer = uv.new_timer,
}

local function read(path)
	return table.concat(vim.fn.readfile(path), "\n")
end

local function test(name, body)
	local directory = vim.fn.tempname()
	vim.fn.mkdir(directory .. "/note with spaces.assets", "p")
	directory = assert(uv.fs_realpath(directory))
	local ctx = {
		directory = directory,
		file = directory .. "/note with spaces.md",
		assets = directory .. "/note with spaces.assets",
		output = directory .. "/exports/result.pdf",
		buf = api.nvim_create_buf(true, false),
		jobs = {},
		pdfs = {},
		notices = {},
		running = {},
	}
	api.nvim_buf_set_name(ctx.buf, ctx.file)
	vim.bo[ctx.buf].filetype = "markdown"
	api.nvim_buf_set_lines(ctx.buf, 0, -1, false, { "# Unsaved note", "", "Conversation context." })
	vim.fn.writefile({ "# Older saved note" }, ctx.file)
	require("diagram_notes.config").setup()
	uv.os_homedir = function()
		return directory .. "/home"
	end
	vim.notify = function(message)
		ctx.notices[#ctx.notices + 1] = message
	end
	viewer.export_problem = function() end
	viewer.export = function(text, base, output, done)
		ctx.pdfs[#ctx.pdfs + 1] = { text = text, directory = base, output = output, done = done }
	end
	renderer.render = function(input, output, options, done)
		local job = { input = input, output = output, options = options, done = done }
		function job:kill()
			self.killed = true
		end
		ctx.jobs[#ctx.jobs + 1] = job
		return job
	end
	function ctx.start(destination)
		local job = export.buffer(ctx.buf, destination, function(err, output)
			ctx.result = { error = err, output = output }
		end)
		ctx.running[#ctx.running + 1] = job
		return job
	end
	function ctx.scene()
		local scene = ctx.assets .. "/overview.excalidraw"
		vim.fn.writefile({ '{"elements":[{"id":"original","backgroundColor":"#ffffff"}]}' }, scene)
		api.nvim_buf_set_lines(ctx.buf, 0, -1, false, { "![Diagram](<note with spaces.assets/overview.png>)" })
		return scene
	end
	function ctx.finish_pdf(err, content)
		local pdf = ctx.pdfs[#ctx.pdfs]
		if not err then
			vim.fn.writefile({ content or "%PDF-1.7 test" }, pdf.output)
		end
		pdf.done(err)
	end
	h.test(name, function()
		body(ctx)
	end, function()
		for _, job in ipairs(ctx.running) do
			job:cancel()
		end
		renderer.render, viewer.export, viewer.export_problem = original.render, original.export, original.problem
		uv.os_homedir, uv.new_timer, vim.notify = original.home, original.timer, original.notify
		api.nvim_buf_delete(ctx.buf, { force = true })
		vim.fn.delete(directory, "rf")
	end)
end

test("the default destination is a named PDF in Downloads", function(ctx)
	ctx.start()
	ctx.finish_pdf()
	local expected = ctx.directory .. "/home/Downloads/note with spaces.pdf"
	h.equal(expected, ctx.result.output)
	h.equal("%PDF-1.7 test", read(expected))
end)

test("export snapshots unsaved Markdown without saving the note", function(ctx)
	ctx.start(ctx.output)
	api.nvim_buf_set_lines(ctx.buf, 0, -1, false, { "Later edit" })
	h.equal("# Unsaved note\n\nConversation context.", ctx.pdfs[1].text)
	h.equal("# Older saved note", read(ctx.file))
	h.equal(true, vim.bo[ctx.buf].modified)
end)

test("diagrams render in the light theme before PDF export starts", function(ctx)
	local scene = ctx.scene()
	local original_scene = read(scene)
	local image = ctx.assets .. "/overview.png"
	vim.fn.writefile({ "existing dark preview" }, image)
	ctx.start(ctx.output)
	h.equal(0, #ctx.pdfs)
	h.equal("light", ctx.jobs[1].options.theme)
	h.equal("transparent", vim.json.decode(ctx.jobs[1].input).elements[1].backgroundColor)
	ctx.jobs[1].done()
	h.equal(1, #ctx.pdfs)
	assert(ctx.pdfs[1].text:find(vim.uri_from_fname(ctx.jobs[1].output), 1, true))
	h.equal(original_scene, read(scene))
	h.equal("existing dark preview", read(image))
end)

test("ordinary local images are copied into the export snapshot", function(ctx)
	local image = ctx.assets .. "/screenshot.png"
	vim.fn.writefile({ "image snapshot" }, image)
	api.nvim_buf_set_lines(ctx.buf, 0, -1, false, { "![Screenshot](<note with spaces.assets/screenshot.png>)" })
	ctx.start(ctx.output)
	local copy = ctx.pdfs[1].text:match("<([^>]+)>")
	h.equal("image snapshot", read(vim.uri_to_fname(copy)))
	h.equal(0, #ctx.jobs)
end)

test("all scenes are snapshotted before sequential rendering begins", function(ctx)
	ctx.scene()
	local second = ctx.assets .. "/second.excalidraw"
	vim.fn.writefile({ '{"elements":[{"id":"original second"}]}' }, second)
	api.nvim_buf_set_lines(ctx.buf, -1, -1, false, { "![Second](<note with spaces.assets/second.png>)" })
	ctx.start(ctx.output)
	vim.fn.writefile({ '{"elements":[{"id":"later edit"}]}' }, second)
	ctx.jobs[1].done()
	h.equal("original second", vim.json.decode(ctx.jobs[2].input).elements[1].id)
	h.equal(0, #ctx.pdfs)
	ctx.jobs[2].done()
	h.equal(1, #ctx.pdfs)
end)

test("reference images are rewritten while code examples and source links keep their text", function(ctx)
	ctx.scene()
	api.nvim_buf_set_lines(ctx.buf, 0, -1, false, {
		"![Diagram][view]",
		"",
		"[view]: <note with spaces.assets/overview.png>",
		"[Drawing source](<note with spaces.assets/overview.excalidraw>)",
		"`![Example](missing.png)`",
		"```markdown",
		"![Example](missing.png)",
		"```",
	})
	ctx.start(ctx.output)
	ctx.jobs[1].done()
	local text = ctx.pdfs[1].text
	assert(text:find("[view]: <" .. vim.uri_from_fname(ctx.jobs[1].output) .. ">", 1, true))
	assert(text:find("[Drawing source](<note with spaces.assets/overview.excalidraw>)", 1, true))
	assert(text:find("`![Example](missing.png)`", 1, true))
	assert(text:find("```markdown\n![Example](missing.png)\n```", 1, true))
end)

test("an image without a scene or PNG fails before PDF generation", function(ctx)
	api.nvim_buf_set_lines(ctx.buf, 0, -1, false, { "![Missing](missing.png)" })
	ctx.start(ctx.output)
	assert(ctx.result.error:find("Could not copy image", 1, true))
	h.equal(0, #ctx.pdfs)
	h.equal({}, vim.fn.glob(ctx.directory .. "/exports/.diagram-export-*", false, true))
end)

test("malformed scene JSON fails before launching either renderer", function(ctx)
	local scene = ctx.scene()
	vim.fn.writefile({ "invalid JSON" }, scene)
	ctx.start(ctx.output)
	assert(ctx.result.error)
	h.equal(0, #ctx.jobs)
	h.equal(0, #ctx.pdfs)
end)

test("a failed diagram render preserves the existing PDF", function(ctx)
	ctx.scene()
	vim.fn.mkdir(vim.fs.dirname(ctx.output), "p")
	vim.fn.writefile({ "%PDF-previous" }, ctx.output)
	ctx.start(ctx.output)
	ctx.jobs[1].done("browser failed")
	h.equal("%PDF-previous", read(ctx.output))
	h.equal(0, #ctx.pdfs)
	h.equal(nil, ctx.result.output)
	h.equal(nil, uv.fs_stat(vim.fs.dirname(ctx.jobs[1].output)))
end)

test("a renderer launch failure cleans the export workspace", function(ctx)
	ctx.scene()
	renderer.render = function()
		return nil, "Excalidraw launcher missing"
	end
	ctx.start(ctx.output)
	h.equal("Excalidraw launcher missing", ctx.result.error)
	h.equal(0, #ctx.pdfs)
	h.equal({}, vim.fn.glob(ctx.directory .. "/exports/.diagram-export-*", false, true))
end)

test("a failed PDF render preserves the previous export and cleans its workspace", function(ctx)
	vim.fn.mkdir(vim.fs.dirname(ctx.output), "p")
	vim.fn.writefile({ "%PDF-previous" }, ctx.output)
	ctx.start(ctx.output)
	ctx.finish_pdf("Chrome unavailable")
	h.equal("%PDF-previous", read(ctx.output))
	h.equal("Chrome unavailable", ctx.result.error)
	h.equal(nil, uv.fs_stat(vim.fs.dirname(ctx.pdfs[1].output)))
end)

test("invalid PDF output is rejected before replacing the destination", function(ctx)
	ctx.start(ctx.output)
	ctx.finish_pdf(nil, "not a PDF")
	h.equal("renderer did not produce a PDF", ctx.result.error)
	h.equal(nil, uv.fs_stat(ctx.output))
end)

test("a successful export atomically replaces the PDF and removes temporary assets", function(ctx)
	vim.fn.mkdir(vim.fs.dirname(ctx.output), "p")
	vim.fn.writefile({ "%PDF-previous" }, ctx.output)
	ctx.start(ctx.output)
	h.equal("%PDF-previous", read(ctx.output))
	ctx.finish_pdf(nil, "%PDF-replacement")
	h.equal("%PDF-replacement", read(ctx.output))
	h.equal(ctx.output, ctx.result.output)
	h.equal(nil, uv.fs_stat(vim.fs.dirname(ctx.pdfs[1].output)))
end)

test("a destination that cannot be replaced reports the filesystem error", function(ctx)
	vim.fn.mkdir(ctx.output, "p")
	ctx.start(ctx.output)
	ctx.finish_pdf()
	assert(ctx.result.error)
	h.equal("directory", uv.fs_stat(ctx.output).type)
	h.equal(nil, uv.fs_stat(vim.fs.dirname(ctx.pdfs[1].output)))
end)

test("an in-flight export owns its output path until completion", function(ctx)
	ctx.start(ctx.output)
	local rejected
	export.buffer(ctx.buf, ctx.output, function(err)
		rejected = err
	end)
	assert(rejected:find("Already exporting", 1, true))
	h.equal(1, #ctx.pdfs)
end)

test("the output path can be exported again after completion", function(ctx)
	ctx.start(ctx.output)
	ctx.finish_pdf()
	ctx.start(ctx.output)
	ctx.finish_pdf(nil, "%PDF-new export")
	h.equal("%PDF-new export", read(ctx.output))
end)

test("exporting a picked note uses its already-loaded unsaved buffer", function(ctx)
	local job = export.file(ctx.file, ctx.output)
	ctx.running[#ctx.running + 1] = job
	h.equal("# Unsaved note\n\nConversation context.", ctx.pdfs[1].text)
end)

test("exporting a closed note reads its file without opening a window", function(ctx)
	local path = ctx.directory .. "/closed.md"
	vim.fn.writefile({ "# Closed note" }, path)
	local win = api.nvim_get_current_win()
	local job = export.file(path, ctx.output)
	ctx.running[#ctx.running + 1] = job
	h.equal("# Closed note", ctx.pdfs[1].text)
	h.equal(win, api.nvim_get_current_win())
	h.equal(-1, vim.fn.bufnr(path))
end)

test("a missing Vellum renderer reports its setup requirement", function(ctx)
	viewer.export_problem = function()
		return "Run :Vellum build"
	end
	ctx.start(ctx.output)
	h.equal("Run :Vellum build", ctx.result.error)
	h.equal(0, #ctx.pdfs)
	h.equal(nil, uv.fs_stat(vim.fs.dirname(ctx.output)))
end)

test("a non-PDF destination is rejected without writing it", function(ctx)
	ctx.start(ctx.directory .. "/result.html")
	assert(ctx.result.error:find("Choose a .pdf destination", 1, true))
	h.equal(0, #ctx.pdfs)
end)

test("a code buffer is rejected instead of exporting the wrong document", function(ctx)
	api.nvim_buf_set_name(ctx.buf, ctx.directory .. "/code.lua")
	vim.bo[ctx.buf].filetype = "lua"
	ctx.start(ctx.output)
	h.equal("Open a Markdown note to export it.", ctx.result.error)
	h.equal(0, #ctx.pdfs)
end)

test("a timed-out export cancels rendering and ignores a late completion", function(ctx)
	local callback
	uv.new_timer = function()
		return {
			start = function(_, _, _, fn)
				callback = fn
			end,
			stop = function() end,
			close = function() end,
		}
	end
	ctx.scene()
	ctx.start(ctx.output)
	callback()
	assert(vim.wait(1000, function()
		return ctx.result ~= nil
	end))
	ctx.jobs[1].done()
	h.equal("renderer timed out", ctx.result.error)
	h.equal(true, ctx.jobs[1].killed)
	h.equal(0, #ctx.pdfs)
	h.equal(nil, uv.fs_stat(ctx.output))
end)

h.finish()
