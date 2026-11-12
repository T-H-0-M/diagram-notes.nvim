if vim.g.loaded_diagram_notes then
	return
end
vim.g.loaded_diagram_notes = true
require("diagram_notes").commands()
