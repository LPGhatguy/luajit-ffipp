--[[
	FFI++ for LuaJIT
	Mangler
]]

local mangler = {
	type_codes = {
		["long long"] = "L",
		["int64_t"] = "L",
		["unsigned long long"] = "l",
		["uint64_t"] = "l",

		["int"] = "I",
		["int32_t"] = "I",
		["unsigned int"] = "i",
		["uint32_t"] = "i",

		["short"] = "S",
		["int16_t"] = "S",
		["unsigned short"] = "s",
		["uint16_t"] = "s",

		["char"] = "C",
		["signed char"] = "C",
		["int8_t"] = "C",
		["unsigned char"] = "c",
		["uint8_t"] = "c",

		["double"] = "D",
		["float"] = "F",

		["void"] = "V"
	}
}

--[[
	string get_type_suffix(Definition definition)
		definition: The C++ method definition to generate a suffix for

	Returns the argument-based suffix a function should have to prevent name clashes.
]]
function mangler.get_type_suffix(definition)
	local buffer = {}

	if (#definition.arguments == 0) then
		return "V"
	end

	for key, argument in ipairs(definition.arguments) do
		local is_pointer = not not argument:match("%*")
		local is_const = not not argument:match("const%s+")
		local is_ref = not not argument:match("&")
		local regular_name = argument:gsub("%s*%*%s*", ""):gsub("const%s+", ""):gsub("%s*&%s*", "")

		if (mangler.type_codes[regular_name]) then
			regular_name = mangler.type_codes[regular_name]
		else
			regular_name = "_" .. regular_name .. "_"
		end

		if (is_ref) then
			regular_name = "R" .. regular_name
		end

		if (is_const) then
			regular_name = "Q" .. regular_name
		end

		if (is_pointer) then
			regular_name = "P" .. regular_name
		end

		table.insert(buffer, regular_name)
	end

	return table.concat(buffer, "")
end

function mangler.mangle(definition)
	local translated = definition.name:gsub(":", "_")
	return translated .. mangler.get_type_suffix(definition)
end

return mangler