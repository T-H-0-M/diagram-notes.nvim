local M = {}

local defaults = {
	picker = "auto",
	debounce_ms = 200,
	render = {
		scale = 2,
		timeout_ms = 120000,
		theme = "dark",
		transparent = true,
		shape_fills = "transparent",
	},
}

function M.setup(opts)
	local options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	local temporary = vim.env.TMPDIR
	if not temporary or temporary == "" then
		temporary = vim.uv.os_tmpdir()
	end
	local directory = options.notes_dir or vim.env.DIAGRAM_NOTES_DIR
	if not directory or directory == "" then
		directory = vim.fs.joinpath(temporary, "diagram-notes")
	end
	assert(type(directory) == "string", "notes_dir must be a path")
	options.notes_dir = vim.fs.abspath(vim.fn.expand(directory))
	assert(vim.tbl_contains({ "auto", "snacks", "select" }, options.picker), "picker must be auto, snacks, or select")
	assert(type(options.debounce_ms) == "number" and options.debounce_ms >= 0, "debounce_ms must be non-negative")
	local render = options.render
	assert(
		type(render.scale) == "number" and render.scale > 0 and render.scale <= 16,
		"render.scale must be in (0, 16]"
	)
	assert(type(render.timeout_ms) == "number" and render.timeout_ms > 0, "render.timeout_ms must be positive")
	assert(vim.tbl_contains({ "light", "dark" }, render.theme), "render.theme must be light or dark")
	assert(type(render.transparent) == "boolean", "render.transparent must be a boolean")
	assert(
		vim.tbl_contains({ "transparent", "preserve" }, render.shape_fills),
		"render.shape_fills must be transparent or preserve"
	)
	if render.command then
		assert(
			type(render.command) == "table" and vim.islist(render.command) and #render.command > 0,
			"render.command must be an argument list"
		)
		for _, argument in ipairs(render.command) do
			assert(type(argument) == "string" and argument ~= "", "render.command arguments must be non-empty strings")
		end
	end
	M.options = options
	return options
end

function M.get()
	return M.options or M.setup()
end

function M.command()
	local configured = M.get().render.command
	if configured then
		return vim.deepcopy(configured)
	end
	return vim.fn.executable("excalidraw") == 1 and { "excalidraw" }
		or { "npx", "--yes", "--package=@excalidraw/cli@0.3.0", "excalidraw" }
end

return M
