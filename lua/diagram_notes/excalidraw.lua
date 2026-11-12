local M = {}
local api, uv = vim.api, vim.uv
local config = require("diagram_notes.config")

local function signature(path)
	local stat = uv.fs_stat(path)
	return stat and stat.type == "file" and { stat.ino, stat.size, stat.mtime, stat.ctime } or nil
end

local function newer(a, b)
	return a.sec > b.sec or (a.sec == b.sec and a.nsec > b.nsec)
end

local function warn(message)
	vim.notify(message, vim.log.levels.WARN, { title = "Excalidraw" })
end

function M.references(buf)
	local scenes, images = {}, {}
	local directory = vim.fs.dirname(api.nvim_buf_get_name(buf)) or vim.fn.getcwd()
	local function add(destination)
		destination = destination:match("^<(.*)>$") or destination
		if destination:match("^%a[%w+.-]*:") or destination:match("^//") then
			return
		end
		destination = vim.uri_decode(destination:match("^[^#?]*")):gsub("\\([%p])", "%1")
		local path = vim.fs.normalize(destination:sub(1, 1) == "/" and destination or directory .. "/" .. destination)
		if path:match("%.excalidraw$") then
			local png = path:gsub("%.excalidraw$", ".png")
			scenes[path], images[png] = png, true
		elseif path:match("%.png$") then
			images[path] = true
			scenes[path:gsub("%.png$", ".excalidraw")] = path
		end
	end

	local parser = vim.treesitter.get_parser(buf, "markdown")
	local blocks = vim.treesitter.query.parse(
		"markdown",
		"[(link_reference_definition (link_destination) @path) (inline) @inline]"
	)
	local links = vim.treesitter.query.parse("markdown_inline", "(link_destination) @path")
	for id, node in blocks:iter_captures(parser:parse()[1]:root(), buf) do
		local text = vim.treesitter.get_node_text(node, buf)
		if blocks.captures[id] == "path" then
			add(text)
		else
			-- Parse only prose inlines, so examples inside code fences never trigger exports.
			local inline = vim.treesitter.get_string_parser(text, "markdown_inline"):parse()[1]
			for _, link in links:iter_captures(inline:root(), text) do
				add(vim.treesitter.get_node_text(link, text))
			end
		end
	end
	return scenes, images
end

local function render_input(path, options)
	local scene = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
	assert(type(scene) == "table" and type(scene.elements) == "table", "Scene must contain an elements array")
	if options.shape_fills == "transparent" then
		for _, element in ipairs(scene.elements) do
			element.backgroundColor = "transparent"
		end
	end
	if not options.transparent then
		scene.appState = type(scene.appState) == "table" and scene.appState or {}
		scene.appState.exportBackground = true
	end
	return vim.json.encode(scene)
end

local function command(output, options)
	local cmd = vim.list_extend(config.command(), {
		"render",
		"-",
		"--out",
		output,
		"--format",
		"png",
		"--scale",
		tostring(options.scale),
		"--theme",
		options.theme,
	})
	if options.transparent then
		cmd[#cmd + 1] = "--transparent"
	end
	return cmd
end

local function png(path)
	local file = io.open(path, "rb")
	if not file then
		return false
	end
	local header = file:read(24)
	file:close()
	return header and #header == 24 and header:sub(1, 8) == "\137PNG\r\n\26\n"
end

local function stop(entry)
	if entry.process then
		entry.process:kill(15)
	end
	if entry.temporary then
		uv.fs_unlink(entry.temporary)
	end
end

function M.watch(buf, on_image)
	local options = config.get()
	local self = { entries = {}, images = {}, watchers = {}, timer = assert(uv.new_timer()) }
	local function schedule()
		if not self.closed then
			self.timer:start(
				options.debounce_ms,
				0,
				vim.schedule_wrap(function()
					self:refresh()
				end)
			)
		end
	end

	local function watch_paths(paths)
		local directories = {}
		for path in pairs(paths) do
			local name, dir = vim.fs.basename(path), vim.fs.dirname(path)
			-- Watch the nearest existing ancestor until an agent creates the asset directory.
			while dir and not uv.fs_stat(dir) do
				name, dir = vim.fs.basename(dir), vim.fs.dirname(dir)
			end
			if dir then
				directories[dir] = directories[dir] or {}
				directories[dir][name] = true
			end
		end
		for dir, watcher in pairs(self.watchers) do
			if not directories[dir] then
				watcher.handle:stop()
				watcher.handle:close()
				self.watchers[dir] = nil
			end
		end
		for dir, names in pairs(directories) do
			if not self.watchers[dir] then
				local watcher = { handle = assert(uv.new_fs_event()) }
				self.watchers[dir] = watcher
				local ok, err = watcher.handle:start(dir, {}, function(event_err, name)
					if not event_err and (not name or watcher.names[name]) then
						schedule()
					end
				end)
				if not ok then
					warn("Could not watch " .. dir .. ": " .. tostring(err))
				end
			end
			self.watchers[dir].names = names
		end
	end

	local function render(scene, entry, version)
		local prepared, input = pcall(render_input, scene, options.render)
		if not prepared then
			entry.failed = version
			return warn("Could not prepare " .. scene .. ": " .. tostring(input))
		end
		local fd, temporary = uv.fs_mkstemp(entry.output .. ".XXXXXX")
		if not fd then
			entry.failed = version
			return warn("Could not create preview beside " .. entry.output .. ": " .. tostring(temporary))
		end
		uv.fs_close(fd)
		entry.temporary = temporary
		local ok, process = pcall(
			vim.system,
			command(temporary, options.render),
			{
				stdin = input,
				text = true,
				timeout = options.render.timeout_ms,
				env = { EXCALIDRAW_NO_UPDATE_NOTIFIER = "1" },
			},
			vim.schedule_wrap(function(result)
				entry.process, entry.temporary = nil, nil
				if self.closed or self.entries[scene] ~= entry then
					uv.fs_unlink(temporary)
					return
				end
				if not vim.deep_equal(version, signature(scene)) then
					uv.fs_unlink(temporary)
					return self:refresh()
				end
				local err
				if result.code ~= 0 then
					err = vim.trim(result.stderr or "")
					if err == "" then
						err = "renderer exited with code " .. result.code
					end
				elseif not png(temporary) then
					err = "renderer did not produce a PNG"
				else
					local renamed
					renamed, err = uv.fs_rename(temporary, entry.output)
					if renamed then
						entry.rendered, entry.failed = version, nil
					end
				end
				if err then
					entry.failed = version
					warn("Export failed for " .. scene .. ": " .. err:sub(-2000))
				end
				uv.fs_unlink(temporary)
				self:refresh()
			end)
		)
		if ok then
			entry.process = process
		else
			entry.failed, entry.temporary = version, nil
			uv.fs_unlink(temporary)
			warn("Could not start Excalidraw (requires Node.js 22+ and npm): " .. tostring(process))
		end
	end

	function self:refresh(force)
		if self.closed or not api.nvim_buf_is_loaded(buf) then
			return
		end
		local scenes, images = M.references(buf)
		local paths = vim.tbl_extend("force", {}, scenes, images)
		watch_paths(paths)
		for scene, entry in pairs(self.entries) do
			if not scenes[scene] then
				self.entries[scene] = nil
				stop(entry)
			end
		end
		for path in pairs(self.images) do
			if not images[path] then
				self.images[path] = nil
			end
		end
		for path in pairs(images) do
			local version = signature(path) or false
			if self.images[path] ~= version and not vim.deep_equal(self.images[path], version) then
				local previous = self.images[path]
				self.images[path] = version
				if previous or version then
					on_image(path)
				end
			end
		end
		for scene, output in pairs(scenes) do
			local version = signature(scene)
			local entry = self.entries[scene] or { output = output }
			self.entries[scene] = entry
			if force then
				entry.force, entry.failed = not entry.process, nil
			end
			if version and not entry.process then
				local exported = signature(output)
				if not entry.rendered and not entry.failed and exported and not newer(version[3], exported[3]) then
					entry.rendered = version
				end
				if
					entry.force
					or (
						not vim.deep_equal(entry.failed, version)
						and (not exported or not vim.deep_equal(entry.rendered, version))
					)
				then
					entry.force = false
					render(scene, entry, version)
				end
			end
		end
	end

	function self:close()
		if self.closed then
			return
		end
		self.closed = true
		self.timer:stop()
		self.timer:close()
		for _, watcher in pairs(self.watchers) do
			watcher.handle:stop()
			watcher.handle:close()
		end
		for _, entry in pairs(self.entries) do
			stop(entry)
		end
	end

	self:refresh()
	return self
end

return M
