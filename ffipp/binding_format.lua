--[[
	FFI++ for Lua
	Binding Format

	Provides a higher level interface than binding_parser and binding_generator for saving/loading bindings.
]]

local parser = require("ffipp.binding_parser")
local generator = require("ffipp.binding_generator")
local format = {}

function format.parse(body)
	return parser.binding(body)
end

function format.load(filename)
	local file = assert(io.open(filename, "rb"))
	local body = file:read()
	file:close()

	return format.parse(body)
end

function format.save(binding)
	error("not implemented")
end

return format