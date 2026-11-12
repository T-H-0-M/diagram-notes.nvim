local M = {}

function M.check()
	local health = vim.health
	health.start("diagram-notes.nvim")
	if vim.fn.has("nvim-0.12") == 1 then
		health.ok("Neovim 0.12+")
	else
		health.error("Neovim 0.12+ is required")
	end
	for _, language in ipairs({ "markdown", "markdown_inline" }) do
		local ok = pcall(vim.treesitter.language.add, language)
		if ok then
			health.ok(language .. " parser available")
		else
			health.error("Install the " .. language .. " Tree-sitter parser")
		end
	end
	local ok, problem = pcall(require("diagram_notes.viewers.vellum").problem)
	if not ok then
		health.error("Install vellum.nvim: " .. tostring(problem))
	elseif problem then
		health.warn(problem)
	else
		health.ok("Vellum terminal graphics available")
	end
	local config = require("diagram_notes.config")
	local executable = config.command()[1]
	if vim.fn.executable(executable) == 1 then
		health.ok("Renderer launcher: " .. executable)
	else
		health.error("Renderer launcher not found: " .. executable)
	end
	if vim.fn.executable("node") == 1 then
		local result = vim.system({ "node", "--version" }, { text = true, timeout = 5000 }):wait()
		local major = tonumber((result.stdout or ""):match("v(%d+)"))
		if major and major >= 22 then
			health.ok("Node.js " .. vim.trim(result.stdout))
		else
			health.warn("The Excalidraw CLI requires Node.js 22+")
		end
	else
		health.warn("The Excalidraw CLI requires Node.js 22+")
	end
	health.info(
		"Rendering requires an installed Chrome, Chromium, Edge, or Firefox. Set EXCALIDRAW_BROWSER_PATH for a custom browser."
	)
	health.info("Notes directory: " .. config.get().notes_dir)
	health.info("Run :checkhealth vellum for Vellum's renderer diagnostics.")
end

return M
