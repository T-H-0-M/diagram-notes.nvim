local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
local excalidraw = require("diagram_notes.excalidraw")
local config = require("diagram_notes.config")
local uv, api = vim.uv, vim.api
local system, notify = vim.system, vim.notify
local passed, failed = 0, 0
local image =
	vim.base64.decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")

local function equal(expected, actual)
	assert(vim.deep_equal(expected, actual), "Expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
end

local function read(path)
	local file = assert(io.open(path, "rb"))
	local data = file:read("*a")
	file:close()
	return data
end

local function wait_for(predicate)
	assert(vim.wait(5000, predicate, 10), "Timed out")
end

local function scene(id)
	return vim.json.encode({
		type = "excalidraw",
		version = 2,
		elements = {
			{ id = id, type = "rectangle", backgroundColor = "#ffffff", strokeColor = "#1e1e1e" },
		},
	})
end

local function test(name, body)
	config.setup()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir .. "/assets", "p")
	dir = assert(uv.fs_realpath(dir))
	local buf = api.nvim_create_buf(true, false)
	api.nvim_buf_set_name(buf, dir .. "/note.md")
	local session, tick = nil, 1700000000
	local ctx = { dir = dir, buf = buf, jobs = {}, notices = {}, changed = {} }
	ctx.scene, ctx.output = dir .. "/assets/overview.excalidraw", dir .. "/assets/overview.png"
	function ctx.write(path, data)
		local file = assert(io.open(path, "wb"))
		file:write(data)
		file:close()
		tick = tick + 1
		assert(uv.fs_utime(path, tick, tick))
	end
	function ctx.link(lines)
		api.nvim_buf_set_lines(buf, 0, -1, false, lines or {
			"![Overview](assets/overview.png)",
			"",
			"[Source](assets/overview.excalidraw)",
		})
	end
	function ctx.watch()
		session = excalidraw.watch(buf, function(path)
			ctx.changed[#ctx.changed + 1] = path
		end)
		return session
	end
	vim.notify = function(message)
		ctx.notices[#ctx.notices + 1] = message
	end
	vim.system = function(command, options, callback)
		local job = { command = command, input = options.stdin, options = options }
		for i, arg in ipairs(command) do
			if arg == "--out" then
				job.output = command[i + 1]
			end
		end
		assert(job.output, "Missing export destination")
		function job:kill()
			self.killed = true
		end
		function job:finish(data, code)
			if data then
				ctx.write(self.output, data)
			end
			callback({ code = code or 0, stderr = code and "Export failed" or "" })
			vim.schedule(function()
				self.completed = true
			end)
			wait_for(function()
				return self.completed
			end)
		end
		ctx.jobs[#ctx.jobs + 1] = job
		return job
	end
	local ok, err = xpcall(function()
		body(ctx)
	end, debug.traceback)
	if session then
		session:close()
	end
	vim.system, vim.notify = system, notify
	api.nvim_buf_delete(buf, { force = true })
	vim.fn.delete(dir, "rf")
	if ok then
		passed = passed + 1
		print("PASS " .. name)
	else
		failed = failed + 1
		io.stderr:write("FAIL " .. name .. "\n" .. err .. "\n")
	end
end

test("discovers document-relative links and skips code examples and URLs", function(ctx)
	ctx.link({
		"![View](<assets/my drawing.png>)",
		"[Source](assets/my%20drawing.excalidraw)",
		"[Other][ref]",
		"",
		"[ref]: assets/other.excalidraw",
		"",
		"[Remote](https://example.com/remote.excalidraw)",
		"`[inline](code.excalidraw)`",
		"",
		"```markdown",
		"[Example](example.excalidraw)",
		"```",
	})
	local scenes = excalidraw.references(ctx.buf)
	equal({
		[ctx.dir .. "/assets/my drawing.excalidraw"] = ctx.dir .. "/assets/my drawing.png",
		[ctx.dir .. "/assets/other.excalidraw"] = ctx.dir .. "/assets/other.png",
	}, scenes)
end)

test("publishes a missing PNG only after export succeeds", function(ctx)
	ctx.write(ctx.scene, '{"elements":[]}')
	ctx.link()
	ctx.watch()
	equal(nil, uv.fs_stat(ctx.output))
	ctx.jobs[1]:finish(image)
	equal(image, read(ctx.output))
	equal({ ctx.output }, ctx.changed)
end)

test("clears shape fills in the render input while preserving the editable scene", function(ctx)
	local drawing = vim.json.decode(scene("box"))
	drawing.elements[2] = { id = "ellipse", type = "ellipse", backgroundColor = "#ff0000", strokeColor = "#0000ff" }
	drawing.appState = { viewBackgroundColor = "#ffffff" }
	local original = vim.json.encode(drawing)
	ctx.write(ctx.scene, original)
	ctx.link()
	ctx.watch()
	drawing.elements[1].backgroundColor = "transparent"
	drawing.elements[2].backgroundColor = "transparent"
	equal(drawing, vim.json.decode(ctx.jobs[1].input))
	equal(original, read(ctx.scene))
end)

test("malformed scene JSON preserves the last good image without launching an export", function(ctx)
	ctx.write(ctx.output, image)
	ctx.write(ctx.scene, '{"elements":[')
	ctx.link()
	ctx.watch()
	equal(0, #ctx.jobs)
	equal(image, read(ctx.output))
	assert(ctx.notices[1]:find("Could not prepare", 1, true))
end)

test("configured renderer arguments and timeout reach the export process", function(ctx)
	config.setup({
		render = { command = { "custom-renderer", "--local" }, theme = "light", scale = 3, timeout_ms = 5000 },
	})
	ctx.write(ctx.scene, scene("box"))
	ctx.link()
	ctx.watch()
	local job = ctx.jobs[1]
	equal({
		"custom-renderer",
		"--local",
		"render",
		"-",
		"--out",
		job.output,
		"--format",
		"png",
		"--scale",
		"3",
		"--theme",
		"light",
		"--transparent",
	}, job.command)
	equal(5000, job.options.timeout)
end)

test("preserved shape fills reach the renderer unchanged", function(ctx)
	config.setup({ render = { shape_fills = "preserve" } })
	local original = scene("box")
	ctx.write(ctx.scene, original)
	ctx.link()
	ctx.watch()
	equal(vim.json.decode(original), vim.json.decode(ctx.jobs[1].input))
end)

test("an opaque canvas overrides a scene's transparent export preference", function(ctx)
	config.setup({ render = { transparent = false } })
	local drawing = vim.json.decode(scene("box"))
	drawing.appState = { exportBackground = false, viewBackgroundColor = "#ffffff" }
	ctx.write(ctx.scene, vim.json.encode(drawing))
	ctx.link()
	ctx.watch()
	local job = ctx.jobs[1]
	equal(false, vim.tbl_contains(job.command, "--transparent"))
	equal(true, vim.json.decode(job.input).appState.exportBackground)
end)

test("a scene without elements is rejected before starting the renderer", function(ctx)
	ctx.write(ctx.scene, "{}")
	ctx.link()
	ctx.watch()
	equal(0, #ctx.jobs)
	assert(ctx.notices[1]:find("Scene must contain an elements array", 1, true))
end)

test("opening an up-to-date drawing does not launch an export", function(ctx)
	ctx.write(ctx.scene, scene("box"))
	ctx.write(ctx.output, image)
	ctx.link()
	ctx.watch()
	equal(0, #ctx.jobs)
end)

test("an atomic agent scene replacement triggers an export without a Markdown edit", function(ctx)
	ctx.write(ctx.scene, scene("old"))
	ctx.write(ctx.output, image)
	ctx.link()
	ctx.watch()
	ctx.write(ctx.scene .. ".new", scene("new"))
	assert(uv.fs_rename(ctx.scene .. ".new", ctx.scene))
	wait_for(function()
		return #ctx.jobs == 1
	end)
	ctx.jobs[1]:finish(image .. "updated")
	equal(image .. "updated", read(ctx.output))
end)

test("same-size image replacement invalidates the displayed image", function(ctx)
	ctx.write(ctx.output, image .. "a")
	ctx.link({ "![View](assets/overview.png)" })
	ctx.watch()
	ctx.changed = {}
	ctx.write(ctx.output .. ".new", image .. "b")
	assert(uv.fs_rename(ctx.output .. ".new", ctx.output))
	wait_for(function()
		return #ctx.changed == 1
	end)
	equal({ ctx.output }, ctx.changed)
	equal(0, #ctx.jobs)
end)

test("an obsolete export cannot replace the latest scene's image", function(ctx)
	ctx.write(ctx.scene, scene("first"))
	ctx.link()
	ctx.watch()
	ctx.write(ctx.scene, scene("second"))
	ctx.jobs[1]:finish(image .. "old")
	equal(nil, uv.fs_stat(ctx.output))
	equal(2, #ctx.jobs)
	ctx.jobs[2]:finish(image .. "latest")
	equal(image .. "latest", read(ctx.output))
end)

test("failed exports preserve the last good image without automatic retry loops", function(ctx)
	ctx.write(ctx.output, image)
	ctx.write(ctx.scene, scene("box"))
	ctx.link()
	local session = ctx.watch()
	ctx.jobs[1]:finish(nil, 1)
	session:refresh()
	equal(image, read(ctx.output))
	equal(1, #ctx.jobs)
	assert(ctx.notices[1]:find("Export failed", 1, true))
end)

test("a successful process with invalid image output preserves the last good PNG", function(ctx)
	ctx.write(ctx.output, image)
	ctx.write(ctx.scene, scene("box"))
	ctx.link()
	ctx.watch()
	ctx.jobs[1]:finish("not a PNG")
	equal(image, read(ctx.output))
	assert(ctx.notices[1]:find("did not produce a PNG", 1, true))
end)

test("manual rendering retries a previously failed export", function(ctx)
	ctx.write(ctx.scene, scene("box"))
	ctx.link()
	local session = ctx.watch()
	ctx.jobs[1]:finish(nil, 1)
	session:refresh(true)
	ctx.jobs[2]:finish(image)
	equal(image, read(ctx.output))
end)

test("closing a preview cancels its export and discards late output", function(ctx)
	ctx.write(ctx.scene, scene("box"))
	ctx.link()
	local session = ctx.watch()
	session:close()
	ctx.jobs[1]:finish(image)
	equal(true, ctx.jobs[1].killed)
	equal(nil, uv.fs_stat(ctx.output))
	equal({}, ctx.changed)
end)

test("removing a drawing link cancels its pending export", function(ctx)
	ctx.write(ctx.scene, scene("box"))
	ctx.link()
	local session = ctx.watch()
	ctx.link({ "# Another topic" })
	session:refresh()
	ctx.jobs[1]:finish(image)
	equal(true, ctx.jobs[1].killed)
	equal(nil, uv.fs_stat(ctx.output))
end)

test("an asset directory created after preview opens is discovered", function(ctx)
	ctx.link({ "![New](created/overview.png)" })
	ctx.watch()
	vim.fn.mkdir(ctx.dir .. "/created", "p")
	ctx.write(ctx.dir .. "/created/overview.excalidraw", scene("box"))
	wait_for(function()
		return #ctx.jobs == 1
	end)
	ctx.jobs[1]:finish(image)
	equal(image, read(ctx.dir .. "/created/overview.png"))
end)

print(("%d passed, %d failed"):format(passed, failed))
vim.cmd(failed == 0 and "qa!" or "cquit 1")
