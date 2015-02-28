--[[
	FFI++ for LuaJIT
	General Utilities
]]

local utility = {}

--[[
	(dictionary to) dictionary_shallow_copy(dictionary from, dictionary? to)
		from: The data source.
		to: The data target.

	Shallow-copies all values from a dictionary.
	Optionally copies into an existing table.
]]
function utility.dictionary_shallow_copy(from, to)
	to = to or {}

	for key, value in pairs(from) do
		to[key] = value
	end
end

--[[
	(array to) array_shallow_copy(array from, array? to)
		from: The data source.
		to: The data target.

	Shallow copies an array.
	Optionally copies into an existing table.
]]
function utility.array_shallow_copy(from, to)
	to = to or {}

	for key, value in ipairs(from) do
		table.insert(to, value)
	end

	return to
end

--[[
	mixed index(indexable item, index key)
		item: The item to query.
		key: The index of the item to search for.

	Functionally equivalent to rawget, with less raw.
	Used alongside pcall to check for valid FFI definitions.
]]
function utility.index(item, key)
	return item[key]
end

return utility