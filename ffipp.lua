--[[
LuaJIT C++ FFI

This is the runtime for FFI++

Type Remangler:
	Members need to be re-mangled to avoid collisions given function with the same name but different arguments.
	This is allowed in C++ and is common practice but isn't allowed in C.
	Since differing only by return type isn't allowed in C++, we don't encode the return type in our names.
	Pointer should come before const in mangled names.

	Pointer to type: P* where * is the type
	Const: Q* where * is the type
	64-bit integer: L for signed, l for unsigned
	32-bit integer: I for signed, i for unsigned
	16-bit integer: S for signed, s for unsigned
	 8-bit integer: C for signed, c for unsigned
	double: D
	float: F
	void: V
	struct: name of struct surrounded by underscores

	Samples:
		MangleMe(const char* str, uint32_t length, void* callback);
		becomes
		MangleMe_PQCiPV

		MeToo(std::string, lib_callback callback);
		becomes
		MeToo__std__string__lib_callback_
]]

local ffi = require("ffi")

local compiler_test_count = 0
local ffipp = {
	version = {1, 0, 0},
	defines = {},
	names = {},
	templates = {},
	parser = {},
	matchers = {},
	cpp = {},
	short_type = {
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
		["int8_t"] = "C",
		["unsigned char"] = "c",
		["uint8_t"] = "c",

		["double"] = "D",
		["float"] = "F",

		["void"] = "V"
	},
	report_generated_code = false --enable for diagnosing codegen problems
}

ffipp.templates.test = [[void %s() asm("%s");]]

--=================--
-- UTILITY METHODS --
--=================--

--[[
	(dictionary to) dictionary_shallow_copy(dictionary from, dictionary to)
		from: The data source.
		to: The data target.

	Shallow-copies all values from from to to.
]]
local function dictionary_shallow_copy(from, to)
	to = to or {}

	for key, value in pairs(from) do
		to[key] = value
	end

	return to
end

local function array_shallow_copy(from, to)
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
local function index(item, key)
	return item[key]
end

--[[
	void cdef(string def)
		def: The definition to use

	Runs a chunk of C code through ffi.cdef and reports it depending on the setting of `report_generated_code`.
]]
local function cdef(def)
	if (ffipp.report_generated_code) then
		print(def)
	end
	ffi.cdef(def)
end

--[[
	string? detect_compiler(Assembly assembly, dictionary test_symbols)
		assembly: The assembly (by default ffi.C, obtained by ffi.load) that contains the symbols.
		test_symbols: A dictionary of symbols mapping compiler names to test symbols.

	Returns the name of the compiler that probably compiled this assembly, or nil if it could not be determined.
]]
local function detect_compiler(assembly, test_symbols)
	assembly = assembly or ffi.C
	local template = ffipp.templates.test

	compiler_test_count = compiler_test_count + 1

	for compiler, symbol in pairs(test_symbols) do
		local name = ("_TEST_%s_%d"):format(compiler, compiler_test_count)

		ffi.cdef(template:format(
			name,
			symbol
		))

		if (pcall(index, assembly, name)) then
			return compiler
		end
	end

	return nil
end

--[[
	string get_argument_list(string[] arguments)
		arguments: A list of arguments a method has.

	Returns a string to be used in an FFI++ template involving a list of arguments.
]]
local function get_argument_list(arguments)
	if (arguments and #arguments > 0) then
		return ", " .. table.concat(arguments, ",")
	else
		return ""
	end
end

--[[
	Assembly?, string? choose_assembly(dictionary binding, Assembly assembly)
		binding: The binding to choose for.
		assembly: A runtime-chosen assembly to use instead of a definition-specified one.

	Chooses an assembly to represent the binding based on the assembly names and test symbols it has.
	Also returns the compiler that compiled the chosen assembly.
]]
local function choose_assembly(binding, assembly)
	local assemblies

	if (type(assembly) == "table") then
		assemblies = assembly
	else
		assemblies = {assembly}
	end

	if (binding.assemblies) then
		for i, try in ipairs(binding.assemblies) do
			local ok, loaded = pcall(ffi.load, try)

			if (ok) then
				table.insert(assemblies, loaded)
			end
		end

		if (#assemblies == 0) then
			error(("Binding contained multiple assembly names (%s), but none of them could be located."):format(
				table.concat(binding.assemblies, ", ")), 3)
		end
	else
		table.insert(assemblies, ffi.C)
	end

	for key, assembly in ipairs(assemblies) do
		local compiler = detect_compiler(assembly, binding.test)

		if (compiler) then
			return assembly, compiler
		end
	end

	error("No suitable assembly-compiler combination was found to load the binding.")
end

--===================--
-- EXPOSED FFI++ API --
--===================--

--[[
	Binding loadfile(string filename, Assembly? assembly)
		filename: The location of the FFI++ binding on disk.
		assembly: An assembly to override the 'assembly' directive of the binding.

	Loads an FFI++ binding from a file and returns the result.
]]
function ffipp.loadfile(filename, assembly)
	local file, err = io.open(filename, "rb")

	if (not file) then
		error(err, 2)
	end

	local contents = file:read("*a")
	file:close()

	return ffipp.load(contents, assembly)
end

--[[
	Binding load(string contents, Assembly? assembly)
		contents: An FFI++ binding in source form.
		assembly: An assembly to override the 'assembly' directive of the binding.

	Loads an FFI++ binding from a string and returns the result.
	This is closer to the style of LuaJIT's C FFI than ffipp.loadfile.
]]
function ffipp.load(contents, assembly)
	local parsed, err = ffipp.parse_binding(contents)

	if (not parsed) then
		return nil, err
	end

	return ffipp.define_binding(parsed)
end

--[[
	BindingDefinition parse_binding(string source)
		source: The binding definition in source form.

	Parses an FFI++ binding file and returns the resulting binding file.
]]
function ffipp.parse_binding(source)
	return ffipp.parser.binding(source)
end

--[[
	dictionary define_binding(Binding binding, Assembly assembly)
		binding: A generated and parsed FFI++ binding structure that maps symbols to their meanings.
		assembly: The assembly (given by the binding by default, or ffi.C if there are none) that contains the symbols.

	Generates code to handle a given C++ binding and creates the necessary symbols.
	A table of symbols is returned.
]]
function ffipp.define_binding(binding, assembly)
	assembly, compiler = choose_assembly(binding, assembly)

	print(("Loading binding for compiler %q..."):format(compiler))

	local info = {
		assembly = assembly,
		compiler = compiler
	}

	local items = {}
	local classes = {}

	if (binding.classes) then
		for i, class in pairs(binding.classes) do
			local defined = ffipp.defines.class(info, class, classes)
			
			dictionary_shallow_copy(defined, items)
		end
	end

	return items
end

--[[
	string get_type_suffix(Definition definition)
		definition: The C++ method definition to generate a suffix for

	Returns the argument-based suffix a function should have to prevent name clashes.
]]
function ffipp.get_type_suffix(definition)
	local buffer = {}

	if (#definition.arguments == 0) then
		return "V"
	end

	for key, argument in ipairs(definition.arguments) do
		local is_pointer = not not argument:match("%*")
		local is_const = not not argument:match("const%s+")
		local regular_name = argument:gsub("%s*%*%s*", ""):gsub("const%s+", "")

		if (ffipp.short_type[regular_name]) then
			regular_name = ffipp.short_type[regular_name]
		else
			regular_name = "_" .. regular_name .. "_"
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

--============================--
-- FFI++ BINDING FILE PARSING --
--============================--

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

function ffipp.parser.binding(source)
	local result = {
		assemblies = {},
		classes = {},
		methods = {}
	}

	assert(matched_parse(ffipp.matchers.binding, source, result))

	return result
end

function ffipp.parser.symbols(source)
	local symbols = {}

	for compiler, symbol in source:gmatch("(%S+)%s+(%S+);") do
		symbols[compiler] = symbol
	end

	return symbols
end

function ffipp.parser.assemblies(source)
	local assemblies = {}

	for assembly in source:gmatch("[^\r\n\t]+") do
		table.insert(assemblies, assembly)
	end

	return assemblies
end

function ffipp.parser.class(source, line)
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

	local ok, line = assert(matched_parse(ffipp.matchers.class, body, class, line))

	return class
end

function ffipp.parser.class_data(source, line)
	local members = {}

	local body = source:match("^data%s*{(.+)}$")

	assert(matched_parse(ffipp.matchers.class_data, body, members, line))

	return members
end

function ffipp.parser.class_methods(source, line)
	local methods = {}

	local body = source:match("^methods%s*{(.+)}$")

	assert(matched_parse(ffipp.matchers.class_methods, body, methods, line))

	return methods
end

-- Top-level symbols
ffipp.matchers.binding = {
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
			local assemblies = ffipp.parser.assemblies(assemblies)

			dictionary_shallow_copy(assemblies, result.assemblies)

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
			local symbols = ffipp.parser.symbols(body)

			result.test = symbols

			return #matched, select(2, matched:gsub("\n", ""))
		end
	end,

	-- class directive
	function(source, result, i, line)
		local matched = source:match("^(class%s+%S+%s*:?[^{]*%b{})", i)

		if (matched) then
			local class = ffipp.parser.class(matched, line)

			table.insert(result.classes, class)

			return #matched, select(2, matched:gsub("\n", ""))
		end
	end
}

-- Class symbols
ffipp.matchers.class = {
	-- spaces, line comments, block comments
	ffipp.matchers.binding[1],
	ffipp.matchers.binding[2],
	ffipp.matchers.binding[3],

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
			local members = ffipp.parser.class_data(matched, line)

			array_shallow_copy(members, result.data)

			return #matched, select(2, matched:gsub("\n", ""))
		end
	end,

	-- methods directive
	function(source, result, i)
		local matched = source:match("^methods%s*%b{}", i)

		if (matched) then
			local methods = ffipp.parser.class_methods(matched, line)

			array_shallow_copy(methods, result.methods)

			return #matched, select(2, matched:gsub("\n", ""))
		end
	end
}

ffipp.matchers.class_data = {
	ffipp.matchers.binding[1],
	ffipp.matchers.binding[2],
	ffipp.matchers.binding[3],

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

ffipp.matchers.class_methods = {
	ffipp.matchers.binding[1],
	ffipp.matchers.binding[2],
	ffipp.matchers.binding[3],

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

			entry.symbols = ffipp.parser.symbols(body)

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

			entry.symbols = ffipp.parser.symbols(body)

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

			entry.symbols = ffipp.parser.symbols(body)

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

			entry.symbols = ffipp.parser.symbols(body)

			table.insert(result, entry)

			return #matched, select(2, matched:gsub("\n", ""))
		end
	end
}

--===================--
-- C CODE GENERATION --
--===================--

ffipp.templates.class_body = [[
{{inherits}}
{{vfptr}}
{{members}}
]]

ffipp.templates.class = [[
typedef struct {
{{class_body}}
} {{name}};
]]

ffipp.templates.member_function_name = "{{classname}}__{{name}}_{{type_suffix}}"
ffipp.templates.member_function = [[{{returns}} __thiscall {{name}}({{classname}}*{{arguments}}) asm("{{symbol}}");]]
ffipp.templates.static_member_function_name = "{{classname}}__{{name}}_{{type_suffix}}"
ffipp.templates.static_member_function = [[{{returns}} __cdecl {{name}}({{arguments}}) asm("{{symbol}}");]]
ffipp.templates.constructor_name = [[{{classname}}__C_{{type_suffix}}]]
ffipp.templates.constructor = [[{{classname}}* __thiscall {{name}}({{classname}}*{{arguments}}) asm("{{symbol}}");]]
ffipp.templates.destructor_name = [[{{classname}}__D_{{type_suffix}}]]
ffipp.templates.destructor = [[void __thiscall {{name}}({{classname}}*{{arguments}}) asm("{{symbol}}");]]

function ffipp.names.class(definition)
	local unmangled = definition.unmangled_name

	if (unmangled) then
		return unmangled
	end

	definition.unmangled_name = definition.name:gsub(":", "_")

	return definition.unmangled_name
end

function ffipp.defines.class_body(info, definition, classes)
	local members_list = {}

	if (definition.data) then
		for i, member in ipairs(definition.data) do
			table.insert(members_list, member .. ";")
		end
	end

	local name = ffipp.names.class(definition)

	local inherits = {}
	if (definition.inherits and #definition.inherits > 0) then
		for key, classname in ipairs(definition.inherits) do
			if (not classes[classname]) then
				error(("Class %q cannot inherit from unknown class %q."):format(name, classname), 4)
				return
			end

			table.insert(inherits, ffipp.defines.class_body(info, classes[classname], classes))
		end
	end

	local vfptr
	if (definition.has_virtuals) then
		vfptr = "void* vfptr_" .. name .. ";"
	else
		vfptr = ""
	end

	local body = ffipp.templates.class_body
		:gsub("{{inherits}}", table.concat(inherits, "\n"))
		:gsub("{{vfptr}}", vfptr)
		:gsub("{{members}}", table.concat(members_list, "\n"))

	return body
end

function ffipp.defines.class(info, definition, classes)
	local name = ffipp.names.class(definition)
	local body = ffipp.defines.class_body(info, definition, classes)

	local def = ffipp.templates.class
		:gsub("{{name}}", name)
		:gsub("{{class_body}}", body)

	cdef(def)

	classes[name] = definition

	local defines = {}

	if (definition.methods) then
		for i, method in pairs(definition.methods) do
			if (ffipp.defines[method.type]) then
				local key, value = ffipp.defines[method.type](info, method, definition)

				if (key and value) then
					defines[key] = value
				end
			end
		end
	end

	return defines
end

function ffipp.names.constructor(definition, class)
	return (
		ffipp.templates.constructor_name
		:gsub("{{classname}}", ffipp.names.class(class))
		:gsub("{{type_suffix}}", ffipp.get_type_suffix(definition))
	)
end

function ffipp.defines.constructor(info, definition, class)
	local name = ffipp.names.constructor(definition, class)

	if (not definition.symbols) then
		print(("No symbols defined for constructor %q: skipping"):format(name))
		return
	end

	local arguments = get_argument_list(definition.arguments)

	local def = ffipp.templates.constructor
		:gsub("{{name}}", name)
		:gsub("{{classname}}", ffipp.names.class(class))
		:gsub("{{arguments}}", arguments)
		:gsub("{{symbol}}", definition.symbols[info.compiler])

	cdef(def)

	return name, info.assembly[name]
end

function ffipp.names.destructor(definition, class)
	return (
		ffipp.templates.destructor_name
		:gsub("{{classname}}", ffipp.names.class(class))
		:gsub("{{type_suffix}}", ffipp.get_type_suffix(definition))
	)
end

function ffipp.defines.destructor(info, definition, class)
	local name = ffipp.names.destructor(definition, class)

	if (not definition.symbols) then
		print(("No symbols defined for destructor %q: skipping"):format(name))
		return
	end

	local arguments = get_argument_list(definition.arguments)

	local def = ffipp.templates.destructor
		:gsub("{{name}}", name)
		:gsub("{{classname}}", ffipp.names.class(class))
		:gsub("{{arguments}}", arguments)
		:gsub("{{symbol}}", definition.symbols[info.compiler])

	cdef(def)

	return name, info.assembly[name]
end

function ffipp.names.member_function(definition, class)
	return (
		ffipp.templates.member_function_name
		:gsub("{{classname}}", ffipp.names.class(class))
		:gsub("{{name}}", definition.name)
		:gsub("{{type_suffix}}", ffipp.get_type_suffix(definition))
	)
end

function ffipp.defines.member_function(info, definition, class)
	local name = ffipp.names.member_function(definition, class)

	if (not definition.symbols) then
		print(("No symbols defined for member function %q: skipping"):format(name))
		return
	end

	if (not definition.symbols[info.compiler]) then
		print(("No symbols defined for member function %q for this compiler: skipping"):format(name))
		return
	end

	local arguments = get_argument_list(definition.arguments)

	local def = ffipp.templates.member_function
		:gsub("{{returns}}", definition.returns)
		:gsub("{{name}}", name)
		:gsub("{{classname}}", ffipp.names.class(class))
		:gsub("{{arguments}}", arguments)
		:gsub("{{symbol}}", definition.symbols[info.compiler])

	cdef(def)

	return name, info.assembly[name]
end

function ffipp.names.static_member_function(definition, class)
	return (
		ffipp.templates.static_member_function_name
		:gsub("{{classname}}", ffipp.names.class(class))
		:gsub("{{name}}", definition.name)
		:gsub("{{type_suffix}}", ffipp.get_type_suffix(definition))
	)
end

function ffipp.defines.static_member_function(info, definition, class)
	local name = ffipp.names.static_member_function(definition, class)

	if (not definition.symbols) then
		print(("No symbols defined for static member function %q: skipping"):format(name))
		return
	end

	local arguments = table.concat(definition.arguments, ", ")

	local def = ffipp.templates.static_member_function
		:gsub("{{returns}}", definition.returns)
		:gsub("{{name}}", name)
		:gsub("{{classname}}", ffipp.names.class(class))
		:gsub("{{arguments}}", arguments)
		:gsub("{{symbol}}", definition.symbols[info.compiler])

	cdef(def)

	return name, info.assembly[name]
end

return ffipp