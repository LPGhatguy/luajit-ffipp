--[[
	FFI++ Binding Generator

	Creates a binding file translating C++ symbols to meaningful data.

	This is a prototype and only supports MSVC on Windows right now.
	Other compilers and platforms are coming soon.
]]

assert(jit, "LuaJIT 2.x is required!")
assert(io.popen, "io.popen is required!")

local args = {...}
local libver = "1.2.0"
local config = {
	lister = (jit.os == "Windows") and "dumpbin" or "nm",
	output = nil, -- defaults to [assembly].ffipp
	_assemblies = {}
}

--[[
	Symbol list interfaces list all the exported symbols in an assembly.
	Lister interfaces must implement the following methods:

	bool platform:available()
	sequence platform:get_symbol_list(string assembly_path)
]]
local listers = {}

--[[
	Compiler interfaces demangle symbols and parse them into useful data.
	They must implement the following methods:
	
	bool compiler:available()
	symbol_data? compiler:demangle(symbol)

	symbol_data looks like the following:
	{
		type = "constructor" -- or destructor, member_function, static_member_function
		classname = "classname",
		arguments = {"int", "std::string"},
		virtual = true/false
	}
]]
local compilers = {}

--===========--
-- UTILITIES --
--===========--

local function array_shallow_copy(from, to)
	to = to or {}

	for i, value in ipairs(from) do
		table.insert(to, value)
	end

	return to
end

local function strip(str)
	return (str:gsub("^%s*", ""):gsub("%s*$", ""))
end

--=========--
-- LISTERS --
--=========--

do
	-- dumpbin /exports [assembly]
	-- resulting format is [ordinal] [hint] [RVA] [symbol] [garbage/RTTI]\n
	local dumpbin = {}
	listers.dumpbin = dumpbin

	function dumpbin:available()
		-- check for dumpbin.exe (msvc's symbol lister)
		local handle = io.popen("dumpbin")
		local body = handle:read("*a")
		handle:close()

		return not not body:match("Microsoft")
	end

	function dumpbin:get_symbol_list(assembly_path)
		local handle = io.popen("dumpbin /exports \"" .. assembly_path .. "\"", "rb")
		local body = handle:read("*a")
		handle:close()

		local symbols = {}
		for symbol in body:gmatch(" +%d+ +%x+ +%x+ +(%S+).-\n") do
			table.insert(symbols, symbol)
		end

		return symbols
	end
end

do
	-- nm -g [assembly]
	-- NOT IMPLEMENTED
	local nm = {}
	listers.nm = nm

	function nm:available()
		return false
	end

	function nm:get_symbol_list(assembly_path)
	end
end

do
	-- readelf -Ws [assembly] | awk '{print $8}'
	-- NOT IMPLEMENTED
	local readelf = {}
	listers.readelf = readelf

	function readelf:available()
		return false
	end

	function readelf:get_symbol_list(assembly_path)
	end
end

--===========--
-- COMPILERS --
--===========--

do
	-- MSVC ABI compilers (MSVC, Clang for Windows, IC++ for Windows)
	local msvc = {}
	compilers.msvc = msvc

	local type_map = {
		__uint8 = "uint8_t",
		__int8 = "int8_t",
		__uint16 = "uint16_t",
		__int16 = "int16_t",
		__uint32 = "uint32_t",
		__int32 = "int32_t",
		__uint64 = "uint64_t",
		__int64 = "int64_t"
	}

	function msvc:available()
		-- check for undname.exe (msvc's symbol demangler)
		local handle = io.popen("undname")
		local body = handle:read("*a")
		handle:close()

		return not not body:match("Microsoft")
	end

	function msvc:demangle(symbol)
		local handle = io.popen("undname " .. symbol, "rb")
		local body = handle:read("*a")
		handle:close()

		local demangled = body:match("is :%- \"([^\"]+)\"")

		-- Probably not an MSVC symbol
		if (demangled == symbol) then
			return nil
		end

		--print(demangled)

		local prefix, convention, name, arguments_string = demangled:match("([%w_ ]*) ([%w_]+) ([%w_:~ ]+)(%b())$")

		-- Probably not a symbol we care about
		-- FIXME: operators fall through here
		if (not prefix) then
			return nil, ("MSVC: Unsupported symbol %q, skipping."):format(symbol)
		end

		-- Strip parens off of argument list
		arguments_string = arguments_string:sub(2, -2)
		local arguments = {}

		-- FIXME: templates with multiple arguments will fail to be parsed correctly
		for argument in arguments_string:gmatch("[^,]+") do
			table.insert(arguments, argument)
		end

		local classname
		local is_constructor
		local is_standalone
		do
			local a, b = name:match("([%w_]+)::([%w_~]+)$")

			is_constructor = a and b and (a == b)

			if (is_constructor) then
				classname = a
			elseif (a and b) then
				classname = a
				name = b
			else
				is_standalone = true
				print("\tSymbol failure:", demangled)
			end
		end

		-- Will this break on anything?
		local is_destructor = not not name:match("~")
		local is_virtual = not not prefix:match("virtual")
		local is_static = not not prefix:match("static")

		prefix = prefix:gsub("virtual", ""):gsub("static", "")

		if (arguments[1] and arguments[1]:match("class %w+ const &")) then
			return nil, "MSVC: Throwing away unnecessary constructor on class " .. classname
		end

		for i, argument in ipairs(arguments) do
			if (type_map[argument]) then
				arguments[i] = type_map[argument]
			end

			local t, rest = argument:match("(%w+) const (.+)")

			if (t) then
				arguments[i] = "const " .. t .. " " .. rest
			end

			arguments[i] = argument:gsub("class%s+", "")
		end

		local out = {
			classname = classname,
			arguments = arguments,
			virtual = is_virtual
		}

		if (is_standalone) then
			out.type = "function"
			out.name = name
			out.returns = strip(prefix)
		elseif (is_constructor) then
			out.type = "constructor"
		elseif (is_destructor) then
			out.type = "destructor"
		elseif (is_static) then
			out.name = name
			out.type = "static_member_function"
			out.returns = strip(prefix)
		else
			out.name = name
			out.type = "member_function"
			out.returns = strip(prefix)
		end

		return out
	end
end

do
	-- Itanium ABI compilers (GCC, Clang for *nix, IC++ for Linux)
	local itanium = {}
	compilers.itanium = itanium

	function itanium:available()
		return false
	end

	function itanium:demangle(symbol)
	end
end

--======--
-- MAIN --
--======--

local function deep_match(a, b, ignore)
	return false--[[
	if (not a or not b) then
		return false
	end

	if (type(a) ~= type(b)) then
		return false
	end

	ignore = ignore or {}

	for key, value in pairs(a) do
		if (not ignore[key]) then
			if (type(value) == "table") then
				if (not deep_match(value, b[key])) then
					return false
				end
			else
				if (not value == b[key]) then
					return false
				end
			end
		end
	end

	return true]]
end

local function main()
	print(("FFI++ Binding Generator %s for LuaJIT Initialized\n"):format(libver))

	-- Parse arguments and throw results into config
	for key, value in ipairs(args) do
		local index, set = value:match("^%-%-([^=]-)=(.*)$")

		if (index and set) then
			config[index] = set
		else
			table.insert(config._assemblies, value)
		end
	end

	local lister = listers[config.lister]
	local have_compilers = {}
	local have_compiler = false

	for key, compiler in pairs(compilers) do
		if (compiler:available()) then
			have_compiler = true
			have_compilers[key] = compiler
		end
	end

	if (not lister) then
		print(("Unknown symbol lister %q, terminating..."):format(config.lister))
		return
	end

	if (not lister:available()) then
		print(("Lister %q could not be found on this system, terminating..."):format(config.lister))
		return
	end

	if (not have_compiler) then
		print("No compiler toolkits were available (undname or c++filt), terminating...")
		return
	end

	if (#config._assemblies == 0) then
		print("No input files, terminating...")
		return
	end

	local compiler_names = {}

	for name in pairs(have_compilers) do
		table.insert(compiler_names, name)
	end

	print("Supported compiler toolkits: " .. table.concat(compiler_names, ", "))

	print("Demangling symbols...")

	config.output = config.output or config._assemblies[1] .. ".ffipp"

	local symbols = {}

	for i, assembly_name in ipairs(config._assemblies) do
		local list = lister:get_symbol_list(assembly_name)
		array_shallow_copy(list, symbols)
	end

	local test_symbols = {}
	local classes = {}
	local symbol_count = 0
	local class_count = 0
	for i, symbol in ipairs(symbols) do
		local demangled, compiler_name, why

		for name, compiler in pairs(have_compilers) do
			local try, err = compiler:demangle(symbol)

			if (try) then
				compiler_name = name
				demangled = try
				break
			elseif (err) then
				why = err
			end
		end

		if (demangled) then
			if (not test_symbols[compiler_name]) then
				test_symbols[compiler_name] = symbol
			end

			symbol_count = symbol_count + 1

			if (demangled.classname) then
				local class = classes[demangled.classname]

				if (not class) then
					class_count = class_count + 1
					classes[demangled.classname] = {
						name = demangled.classname,
						has_virtuals = false,
						data = {},
						methods = {}
					}
					class = classes[demangled.classname]
				end

				if (demangled.virtual) then
					class.has_virtuals = true
				end

				local existing
				for key, method in ipairs(class.methods) do
					if (deep_match(demangled, method, {symbols = true})) then
						existing = method
						break
					end
				end

				if (existing) then
					table.insert(existing.symbols, compiler_name .. " " .. symbol)
				else
					table.insert(class.methods, demangled)
					demangled.symbols = {compiler_name .. " " .. symbol}
				end
			else
				print("symbol is standalone, not supported in 0.1.0")
			end
		else
			if (why) then
				print(why)
			else
				print(("Could not find compiler to demangle symbol %q, skipping..."):format(symbol))
			end
		end
	end

	print("\nBinding data generated!")
	print(("Bound %d symbols in %d classes.\n"):format(symbol_count, class_count))

	print("Generating ffipp binding code...")
	local buffer = {}

	-- assemblies directive
	table.insert(buffer, ("assemblies {\n%s\n}"):format(table.concat(config._assemblies, "\n")))

	-- test symbols directive
	local tests = {}
	for key, value in pairs(test_symbols) do
		table.insert(tests, key .. " " .. value .. ";")
	end
	table.insert(buffer, ("test {\n%s\n}"):format(table.concat(tests, "\n\t")))

	-- classes
	for name, class in pairs(classes) do
		local body_buffer = {}

		if (class.has_virtuals) then
			table.insert(body_buffer, "has_virtuals;")
		end

		table.insert(body_buffer, "data {\n\t// fill this in\n}\n")

		local method_buffer = {}
		for key, method in ipairs(class.methods) do
			if (method.type == "constructor") then
				table.insert(method_buffer, ("!(%s) {"):format(table.concat(method.arguments, ", ")))
			elseif (method.type == "destructor") then
				table.insert(method_buffer, ("~(%s) {"):format(table.concat(method.arguments, ", ")))
			elseif (method.type == "member_function") then
				table.insert(method_buffer, ("%s %s(%s) {"):format(method.returns, method.name, table.concat(method.arguments, ", ")))
			elseif (method.type == "static_member_function") then
				table.insert(method_buffer, ("static %s %s(%s) {"):format(method.returns, method.name, table.concat(method.arguments, ", ")))
			end

			for i, symbol in ipairs(method.symbols) do
				method.symbols[i] = symbol .. ";"
			end

			table.insert(method_buffer, table.concat(method.symbols, "\n") .. "\n}")
		end

		table.insert(body_buffer, ("methods {\n%s\n}"):format(table.concat(method_buffer, "\n")))

		table.insert(buffer, ("class %s {\n%s\n}"):format(name, table.concat(body_buffer, "\n")))
	end

	local output = table.concat(buffer, "\n")

	print("\nWriting to file...")
	local handle, err = io.open(config.output, "wb")

	if (not handle) then
		print("IO error: " .. err)
		return
	end

	handle:write(output)
	handle:close()

	print("\nDone!")
	print(("Output: %s"):format(config.output))
end

main()