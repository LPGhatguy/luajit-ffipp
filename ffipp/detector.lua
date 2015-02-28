--[[
	FFI++ for LuaJIT
	Detector

	Locates assemblies and determines the compiler used to compile them.
]]

local ffi = require("ffi")
local utility = require("ffipp.utility")

local detector = {}

local compiler_test_count = 0
local test_template = [[void %s() asm("%s");]]

--[[
	string? detect_compiler(Assembly assembly, dictionary test_symbols)
		assembly: The assembly (by default ffi.C, obtained by ffi.load) that contains the symbols.
		test_symbols: A dictionary of symbols mapping compiler names to test symbols.

	Returns the name of the compiler that probably compiled this assembly, or nil if it could not be determined.
]]
function detector.compiler(assembly, test_symbols)
	assembly = assembly or ffi.C
	local template = test_template

	compiler_test_count = compiler_test_count + 1

	for compiler, symbol in pairs(test_symbols) do
		local name = ("_TEST_%s_%d"):format(compiler, compiler_test_count)

		ffi.cdef(template:format(
			name,
			symbol
		))

		if (pcall(utility.index, assembly, name)) then
			return compiler
		end
	end

	return nil
end

--[[
	Assembly?, string? choose_assembly(dictionary binding, Assembly assembly)
		binding: The binding to choose for.
		assembly: A runtime-chosen assembly to use instead of a definition-specified one.

	Chooses an assembly to represent the binding based on the assembly names and test symbols it has.
	Also returns the compiler that compiled the chosen assembly.
]]
function detector.choose_assembly(binding, assembly)
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
		local compiler = detector.compiler(assembly, binding.test)

		if (compiler) then
			return assembly, compiler
		end
	end

	error("No suitable assembly-compiler combination was found to load the binding.")
end

return detector