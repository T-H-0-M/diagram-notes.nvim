local M = {}
local api, uv = vim.api, vim.uv
local renderer = require("diagram_notes.excalidraw")
local links = require("diagram_notes.links")
local viewer = require("diagram_notes.viewers.vellum")
local running = {}

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "Diagram export" })
end

local function prepare(note, workspace, options)
	local directory = note.file ~= "" and vim.fs.dirname(note.file) or vim.fn.getcwd()
	local destinations = links.destinations(note.text)
	local images, tasks = {}, {}
	local count = 0
	for _, item in ipairs(destinations) do
		local path = item.image and links.path(item.destination, directory)
		if path then
			if not images[path] then
				count = count + 1
				local scene = path:match("%.excalidraw$") and path
					or (path:match("%.png$") and path:gsub("%.png$", ".excalidraw"))
				if scene and uv.fs_stat(scene) then
					images[path] = workspace .. "/image-" .. count .. ".png"
					tasks[#tasks + 1] = {
						input = renderer.prepare(scene, options),
						output = images[path],
						scene = scene,
					}
				else
					images[path] = workspace .. "/image-" .. count .. (path:match("%.[%w]+$") or "")
					local copied, err = uv.fs_copyfile(path, images[path])
					assert(copied, "Could not copy image " .. path .. ": " .. tostring(err))
				end
			end
			item.replacement = "<" .. vim.uri_from_fname(images[path]) .. ">"
		end
	end
	table.sort(destinations, function(a, b)
		return a.first > b.first
	end)
	local text = note.text
	for _, item in ipairs(destinations) do
		if item.replacement then
			text = text:sub(1, item.first) .. item.replacement .. text:sub(item.last + 1)
		end
	end
	return { text = text, directory = directory, tasks = tasks }
end

local function start(note, destination, done)
	local function reject(err)
		notify(tostring(err), vim.log.levels.ERROR)
		if done then
			done(tostring(err))
		end
	end
	if not destination or destination == "" then
		local name = note.file ~= "" and vim.fs.basename(note.file):gsub("%.[^.]+$", "") or "untitled"
		destination = vim.fs.joinpath(uv.os_homedir(), "Downloads", name .. ".pdf")
	else
		destination = vim.fs.abspath(vim.fn.expand(destination))
	end
	if not destination:lower():match("%.pdf$") then
		return reject("Choose a .pdf destination: " .. destination)
	end
	local ok, problem = pcall(viewer.export_problem)
	if not ok or problem then
		return reject(problem)
	end
	local directory = vim.fs.dirname(destination)
	ok, problem = pcall(vim.fn.mkdir, directory, "p")
	if not ok then
		return reject(problem)
	end
	destination = vim.fs.joinpath(uv.fs_realpath(directory) or directory, vim.fs.basename(destination))
	if running[destination] then
		return reject("Already exporting to " .. destination)
	end
	local workspace, err = uv.fs_mkdtemp(directory .. "/.diagram-export-XXXXXX")
	if not workspace then
		return reject(err)
	end
	local options = vim.deepcopy(require("diagram_notes.config").get().render)
	options.theme, options.transparent = "light", true
	options.command = require("diagram_notes.config").command()
	local prepared, document = pcall(prepare, note, workspace, options)
	if not prepared then
		vim.fn.delete(workspace, "rf")
		return reject(document)
	end

	local job = { timer = assert(uv.new_timer()) }
	running[destination] = job
	local function finish(failure)
		if job.closed then
			return
		end
		job.closed = true
		running[destination] = nil
		job.timer:stop()
		job.timer:close()
		if job.process then
			pcall(job.process.kill, job.process, 15)
		end
		vim.fn.delete(workspace, "rf")
		notify(
			failure and ("Export failed: " .. tostring(failure)) or ("Exported PDF: " .. destination),
			failure and vim.log.levels.ERROR or vim.log.levels.INFO
		)
		if done then
			done(failure, not failure and destination or nil)
		end
	end
	function job:cancel()
		finish("cancelled")
	end
	local function arm()
		job.timer:start(
			options.timeout_ms,
			0,
			vim.schedule_wrap(function()
				finish("renderer timed out")
			end)
		)
	end
	local function publish(failure)
		if job.closed then
			return
		end
		if failure then
			return finish(failure)
		end
		local pdf = workspace .. "/document.pdf"
		local file = io.open(pdf, "rb")
		local header = file and file:read(5)
		if file then
			file:close()
		end
		if header ~= "%PDF-" then
			return finish("renderer did not produce a PDF")
		end
		local renamed, rename_error = uv.fs_rename(pdf, destination)
		finish(not renamed and rename_error or nil)
	end
	local index = 0
	local function advance()
		if job.closed then
			return
		end
		arm()
		index = index + 1
		local task = document.tasks[index]
		if not task then
			local exported, failure =
				pcall(viewer.export, document.text, document.directory, workspace .. "/document.pdf", publish)
			if not exported then
				finish(failure)
			end
			return
		end
		local process, failure = renderer.render(task.input, task.output, options, function(render_error)
			job.process = nil
			if render_error then
				finish(task.scene .. ": " .. render_error)
			else
				advance()
			end
		end)
		job.process = process
		if not process then
			finish(failure)
		end
	end
	notify("Exporting PDF: " .. destination)
	advance()
	return job
end

function M.buffer(buf, destination, done)
	local name = api.nvim_buf_get_name(buf)
	if
		vim.bo[buf].buftype ~= ""
		or not (
			vim.tbl_contains({ "markdown", "mdx" }, vim.bo[buf].filetype)
			or name:match("%.mdx?$")
			or name:match("%.markdown$")
		)
	then
		local err = "Open a Markdown note to export it."
		notify(err, vim.log.levels.WARN)
		if done then
			done(err)
		end
		return
	end
	local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
	if vim.bo[buf].filetype == "mdx" or name:match("%.mdx$") then
		local ok, result = pcall(function()
			return require("vellum.mdx").lines(buf)
		end)
		if not ok then
			notify(tostring(result), vim.log.levels.ERROR)
			if done then
				done(tostring(result))
			end
			return
		end
		lines = result
	end
	return start({ file = name, text = table.concat(lines, "\n") }, destination, done)
end

function M.file(path, destination, done)
	local buf = vim.fn.bufnr(path)
	if buf ~= -1 and api.nvim_buf_is_loaded(buf) then
		return M.buffer(buf, destination, done)
	end
	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok then
		notify(tostring(lines), vim.log.levels.ERROR)
		if done then
			done(tostring(lines))
		end
		return
	end
	return start({ file = vim.fs.abspath(path), text = table.concat(lines, "\n") }, destination, done)
end

api.nvim_create_autocmd("VimLeavePre", {
	group = api.nvim_create_augroup("DiagramNotesExports", { clear = true }),
	callback = function()
		for _, job in pairs(running) do
			job:cancel()
		end
	end,
})

return M
