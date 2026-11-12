local M = {}

local function child(node, kind)
	for item in node:iter_children() do
		if item:type() == kind then
			return item
		end
	end
end

local function label(text)
	return vim.trim(text:gsub("%s+", " ")):lower()
end

function M.destinations(source)
	local parser = type(source) == "string" and vim.treesitter.get_string_parser(source, "markdown")
		or vim.treesitter.get_parser(source, "markdown")
	local blocks = vim.treesitter.query.parse(
		"markdown",
		"[(link_reference_definition (link_destination) @path) (inline) @inline]"
	)
	local inlines = vim.treesitter.query.parse("markdown_inline", "[(link_destination) @path (image) @image]")
	local result, definitions, images = {}, {}, {}
	local function add(node, text, offset)
		local _, _, first = node:start()
		local _, _, last = node:end_()
		local item = {
			destination = vim.treesitter.get_node_text(node, text),
			first = offset + first,
			last = offset + last,
			image = node:parent():type() == "image",
		}
		result[#result + 1] = item
		return item
	end
	for id, node in blocks:iter_captures(parser:parse()[1]:root(), source) do
		if blocks.captures[id] == "path" then
			local item = add(node, source, 0)
			local name = vim.treesitter.get_node_text(child(node:parent(), "link_label"), source):sub(2, -2)
			definitions[label(name)] = definitions[label(name)] or item
		else
			local text = vim.treesitter.get_node_text(node, source)
			local _, _, offset = node:start()
			local inline = vim.treesitter.get_string_parser(text, "markdown_inline"):parse()[1]
			for capture, part in inlines:iter_captures(inline:root(), text) do
				if inlines.captures[capture] == "path" then
					add(part, text, offset)
				elseif not child(part, "link_destination") then
					local reference = child(part, "link_label")
					local description = child(part, "image_description")
					local name = reference and vim.treesitter.get_node_text(reference, text):sub(2, -2)
						or (description and vim.treesitter.get_node_text(description, text) or "")
					images[label(name)] = true
				end
			end
		end
	end
	for name in pairs(images) do
		if definitions[name] then
			definitions[name].image = true
		end
	end
	return result
end

function M.path(destination, directory)
	destination = destination:match("^<(.*)>$") or destination
	if destination:match("^%a[%w+.-]*:") or destination:match("^//") then
		return
	end
	destination = vim.uri_decode(destination:match("^[^#?]*")):gsub("\\([%p])", "%1")
	if destination == "" then
		return
	end
	return vim.fs.normalize(destination:sub(1, 1) == "/" and destination or directory .. "/" .. destination, {
		expand_env = false,
	})
end

return M
