--[[
	FFI++ for Lua
	Binding Parser

	Parses string-format FFI++ binding files into their full format.
]]

local utility = require("ffipp.utility")
local parser = {
	matchers = {}
}

local function matched_parse(matchers, source, result, line)
	line = line or 0
	local i = 1

	while (i <= #source) do
		local char = source:sub(i, i)
		local matched = false

		for key, matcher in ipairs(matchers) do
			local count, line_count = matcher(source, result, i, line)

			if (count) then
				matched = true
				i = i + count

				if (line_count) then
					line = line + line_count
				end
			end
		end

		if (not matched) then
			if (char:match("%w")) then
				char = source:match("^%w+", i) or char
			end

			return nil, ("Error on line %d: unexpected token %q"):format(line, char)
		end
	end

	return true, line
end

local function strip(str)
	return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

function parser.binding(source)
	local result = {
		assemblies = {},
		classes = {},
		methods = {}
	}

	assert(matched_parse(parser.matchers.binding, source, result))

	return result
end

function parser.symbols(source)
	local symbols = {}

	for compiler, symbol in source:gmatch("(%S+)%s+(%S+);") do
		symbols[compiler] = symbol
	end

	return symbols
end

function parser.assemblies(source)
	local assemblies = {}

	for assembly in source:gmatch("[^\r\n\t]+") do
		table.insert(assemblies, assembly)
	end

	return assemblies
end

function parser.class(source, line)
	local class = {
		inherits = {},
		data = {},
		methods = {}
	}

	local name, inherits_string, body = source:match("^class%s+(%S+)%s*:?%s*([^{]*)%s*{(.+)}$")

	for item in inherits_string:gmatch("[^,%s]+") do
		table.insert(class.inherits, item)
	end

	class.name = name

	local ok, line = assert(matched_parse(parser.matchers.class, body, class, line))

	return class
end

function parser.class_data(source, line)
	local members = {}

	local body = source:match("^data%s*{(.+)}$")

	assert(matched_parse(parser.matchers.class_data, body, members, line))

	return members
end

function parser.class_methods(source, line)
	local methods = {}

	local body = source:match("^methods%s*{(.+)}$")

	assert(matched_parse(parser.matchers.class_methods, body, methods, line))

	return methods
end

-- Top-level symbols
parser.matchers.binding = {
	-- spaces
	function(source, result, i)
		local matched = source:match("^%s+", i)

		if (matched) then
			return #matched, select(2, matched:gsub("\n", ""))
		end
	end,

	-- line comments
	function(source, result, i)
		local matched = source:match("^//[^\n]*\n?", i)

		if (matched) then
			return #matched, select(2, matched:gsub("\n", ""))
		end
	end,

	-- block comments
	function(source, result, i)
		local matched = source:match("^/%*.-%*/", i)

		if (matched) then
			return #matched, select(2, matched:gsub("\n", ""))
		end
	end,

	-- assemblies directive
	function(source, result, i)
		local matched, assemblies = source:match("^(assemblies%s*{([^}]*)})", i)

		if (matched) then
			local assemblies = parser.assemblies(assemblies)

			utility.dictionary_shallow_copy(assemblies, result.assemblies)

			return #matched, select(2, matched:gsub("\n", ""))
		end
	end,

	--assembly directive
	function(source, result, i)
		local matched, assembly = source:match("^(assembly%s*\"([^\"]*)\")", i)

		if (matched) then
			table.insert(result.assemblies, assembly)

			return #matched, select(2, matched:gsub("\n", ""))
		end
	end,

	-- test symbols directive
	function(source, result, i)
		local matched, body = source:match("^(test%s*{([^}]*)})", i)

		if (matched) then
			local symbols = parser.symbols(body)

			result.test = symbols

			return #matched, select(2, matched:gsub("\n", ""))
		end
	end,

	-- class directive
	function(source, result, i, line)
		local matched = source:match("^(class%s+%S+%s*:?[^{]*%b{})", i)

		if (matched) then
			local class = parser.class(matched, line)

			table.insert(result.classes, class)

			return #matched, select(2, matched:gsub("\n", ""))
		end
	end
}

-- Class symbols
parser.matchers.class = {
	-- spaces, line comments, block comments
	parser.matchers.binding[1],
	parser.matchers.binding[2],
	parser.matchers.binding[3],

	-- has_virtuals directive
	function(source, result, i)
		local matched = source:match("^has_virtuals;", i)

		if (matched) then
			result.has_virtuals = true

			return #matched, select(2, matched:gsub("\n", ""))
		end
	end,

	-- data directive
	function(source, result, i)
		local matched = source:match("^data%s*%b{}", i)

		if (matched) then
			local members = parser.class_data(matched, line)

			utility.array_shallow_copy(members, result.data)

			return #matched, select(2, matched:gsub("\n", ""))
		end
	end,

	-- methods directive
	function(source, result, i)
		local matched = source:match("^methods%s*%b{}", i)

		if (matched) then
			local methods = parser.class_methods(matched, line)

			utility.array_shallow_copy(methods, result.methods)

			return #matched, select(2, matched:gsub("\n", ""))
		end
	end
}

parser.matchers.class_data = {
	parser.matchers.binding[1],
	parser.matchers.binding[2],
	parser.matchers.binding[3],

	-- class data member
	function(source, result, i)
		local matched, type, name = source:match("^((%S+)%s+(%S+);)", i)

		if (matched) then
			local entry = ("%s %s"):format(type, name)

			table.insert(result, entry)

			return #matched, select(2, matched:gsub("\n", ""))
		end
	end
}

parser.matchers.class_methods = {
	parser.matchers.binding[1],
	parser.matchers.binding[2],
	parser.matchers.binding[3],

	-- constructor
	function(source, result, i)
		local matched, arguments, body = source:match("^(!%(([^%)]*)%)%s*{([^}]*)})", i)

		if (matched) then
			local entry = {
				type = "constructor",
				arguments = {},
			}

			for argument in arguments:gmatch("[^,]+") do
				table.insert(entry.arguments, strip(argument))
			end

			entry.symbols = parser.symbols(body)

			table.insert(result, entry)

			return #matched, select(2, matched:gsub("\n", ""))
		end
	end,

	-- destructor
	function(source, result, i)
		local matched, arguments, body = source:match("^(~%(([^%)]*)%)%s*{([^}]*)})", i)

		if (matched) then
			local entry = {
				type = "destructor",
				arguments = {},
			}

			for argument in arguments:gmatch("[^,]+") do
				table.insert(entry.arguments, strip(argument))
			end

			entry.symbols = parser.symbols(body)

			table.insert(result, entry)

			return #matched, select(2, matched:gsub("\n", ""))
		end
	end,

	-- member function
	function(source, result, i)
		local matched, returns, name, arguments, body = source:match("^(([%w%s%*]+)%s+([%w%*]+)%(([^%)]*)%)%s*(%b{}))", i)

		if (matched) then
			if (returns:match("%s*static%s*")) then
				return
			end
			
			body = body:sub(2, -2)
			local entry = {
				type = "member_function",
				name = name,
				returns = returns,
				arguments = {},
			}

			for argument in arguments:gmatch("[^,]+") do
				table.insert(entry.arguments, strip(argument))
			end

			entry.symbols = parser.symbols(body)

			table.insert(result, entry)

			return #matched, select(2, matched:gsub("\n", ""))
		end
	end,

	-- static member function
	function(source, result, i)
		local matched, returns, name, arguments, body = source:match("^(static%s+([%w%s%*]+)%s+([%w%*]+)%(([^%)]*)%)%s*(%b{}))", i)

		if (matched) then
			body = body:sub(2, -2)
			local entry = {
				type = "static_member_function",
				name = name,
				returns = returns,
				arguments = {},
			}

			for argument in arguments:gmatch("[^,]+") do
				table.insert(entry.arguments, strip(argument))
			end

			entry.symbols = parser.symbols(body)

			table.insert(result, entry)

			return #matched, select(2, matched:gsub("\n", ""))
		end
	end
}

return parser