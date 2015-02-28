--[[
LuaJIT C++ FFI

This is the runtime for FFI++

Type Remangler:
	Members need to be re-mangled to avoid collisions given function with the same name but different arguments.
	This is allowed in C++ and is common practice but isn't allowed in C.
	Since differing only by return type isn't allowed in C++, we don't encode the return type in our names.

	Reference types: R* where * is the type
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

local code_generator = require("ffipp.code_generator")
local binding_format = require("ffipp.binding_format")
local detector = require("ffipp.detector")
local utility = require("ffipp.utility")

local ffipp = {
	version = {1, 3, 0, "alpha"},
	version_string = "1.3.0-alpha"
}

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
	local parsed, err = binding_format.parse(contents)

	if (not parsed) then
		return nil, err
	end

	return ffipp.define_binding(parsed)
end

--[[
	dictionary define_binding(Binding binding, Assembly assembly)
		binding: A generated and parsed FFI++ binding structure that maps symbols to their meanings.
		assembly: The assembly (given by the binding by default, or ffi.C if there are none) that contains the symbols.

	Generates code to handle a given C++ binding and creates the necessary symbols.
	A table of symbols is returned.
]]
function ffipp.define_binding(binding, assembly)
	assembly, compiler = detector.choose_assembly(binding, assembly)

	print(("Loading binding for compiler %q..."):format(compiler))

	local info = {
		assembly = assembly,
		compiler = compiler
	}

	local items = {}
	local classes = {}

	if (binding.classes) then
		for i, class in pairs(binding.classes) do
			local defined = code_generator.defines.class(info, class, classes)
			
			utility.dictionary_shallow_copy(defined, items)
		end
	end

	return items
end

return ffipp