--[[
	FFI++ for LuaJIT
	Code Generator

	Generates C code to be used by the regular C FFI.
]]

local ffi = require("ffi")

local mangler = require("ffipp.mangler")
local generator = {
	defines = {},
	names = {},
	templates = {},
	report_code = true
}

generator.templates.class_body = [[
{{inherits}}
{{vfptr}}
{{members}}
]]

generator.templates.class = [[
typedef struct {
{{class_body}}
} {{name}};
]]

generator.templates.member_function_name = [[{{classname}}__{{name}}_{{type_suffix}}]]
generator.templates.member_function = [[{{returns}} __thiscall {{name}}({{classname}}*{{arguments}}) asm("{{symbol}}");]]
generator.templates.static_member_function_name = [[{{classname}}__{{name}}_{{type_suffix}}]]
generator.templates.static_member_function = [[{{returns}} __cdecl {{name}}({{arguments}}) asm("{{symbol}}");]]
generator.templates.constructor_name = [[{{classname}}__C_{{type_suffix}}]]
generator.templates.constructor = [[{{classname}}* __thiscall {{name}}({{classname}}*{{arguments}}) asm("{{symbol}}");]]
generator.templates.destructor_name = [[{{classname}}__D_{{type_suffix}}]]
generator.templates.destructor = [[void __thiscall {{name}}({{classname}}*{{arguments}}) asm("{{symbol}}");]]

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

local function cdef(block)
	if (generator.report_code) then
		print(block)
	end
	ffi.cdef(block)
end

function generator.names.class(definition)
	local unmangled = definition.unmangled_name

	if (unmangled) then
		return unmangled
	end

	definition.unmangled_name = definition.name:gsub(":", "_")

	return definition.unmangled_name
end

function generator.defines.class_body(info, definition, classes)
	local members_list = {}

	if (definition.data) then
		for i, member in ipairs(definition.data) do
			table.insert(members_list, member .. ";")
		end
	end

	local name = generator.names.class(definition)

	local inherits = {}
	if (definition.inherits and #definition.inherits > 0) then
		for key, classname in ipairs(definition.inherits) do
			if (not classes[classname]) then
				error(("Class %q cannot inherit from unknown class %q."):format(name, classname), 4)
				return
			end

			table.insert(inherits, generator.defines.class_body(info, classes[classname], classes))
		end
	end

	local vfptr
	if (definition.has_virtuals) then
		vfptr = "void* vfptr_" .. name .. ";"
	else
		vfptr = ""
	end

	local body = generator.templates.class_body
		:gsub("{{inherits}}", table.concat(inherits, "\n"))
		:gsub("{{vfptr}}", vfptr)
		:gsub("{{members}}", table.concat(members_list, "\n"))

	return body
end

function generator.defines.class(info, definition, classes)
	local name = generator.names.class(definition)
	local body = generator.defines.class_body(info, definition, classes)

	local def = generator.templates.class
		:gsub("{{name}}", name)
		:gsub("{{class_body}}", body)

	cdef(def)

	classes[name] = definition

	local defines = {}

	if (definition.methods) then
		for i, method in pairs(definition.methods) do
			if (generator.defines[method.type]) then
				local key, value = generator.defines[method.type](info, method, definition)

				if (key and value) then
					defines[key] = value
				end
			end
		end
	end

	defines[name] = ffi.typeof(name .. "[1]")

	return defines
end

function generator.names.constructor(definition, class)
	return (
		generator.templates.constructor_name
		:gsub("{{classname}}", generator.names.class(class))
		:gsub("{{type_suffix}}", mangler.get_type_suffix(definition))
	)
end

function generator.defines.constructor(info, definition, class)
	local name = generator.names.constructor(definition, class)

	if (not definition.symbols) then
		print(("No symbols defined for constructor %q: skipping"):format(name))
		return
	end

	local arguments = get_argument_list(definition.arguments)

	local def = generator.templates.constructor
		:gsub("{{name}}", name)
		:gsub("{{classname}}", generator.names.class(class))
		:gsub("{{arguments}}", arguments)
		:gsub("{{symbol}}", definition.symbols[info.compiler])

	cdef(def)

	return name, info.assembly[name]
end

function generator.names.destructor(definition, class)
	return (
		generator.templates.destructor_name
		:gsub("{{classname}}", generator.names.class(class))
		:gsub("{{type_suffix}}", mangler.get_type_suffix(definition))
	)
end

function generator.defines.destructor(info, definition, class)
	local name = generator.names.destructor(definition, class)

	if (not definition.symbols) then
		print(("No symbols defined for destructor %q: skipping"):format(name))
		return
	end

	local arguments = get_argument_list(definition.arguments)

	local def = generator.templates.destructor
		:gsub("{{name}}", name)
		:gsub("{{classname}}", generator.names.class(class))
		:gsub("{{arguments}}", arguments)
		:gsub("{{symbol}}", definition.symbols[info.compiler])

	cdef(def)

	return name, info.assembly[name]
end

function generator.names.member_function(definition, class)
	return (
		generator.templates.member_function_name
		:gsub("{{classname}}", generator.names.class(class))
		:gsub("{{name}}", definition.name)
		:gsub("{{type_suffix}}", mangler.get_type_suffix(definition))
	)
end

function generator.defines.member_function(info, definition, class)
	local name = generator.names.member_function(definition, class)

	if (not definition.symbols) then
		print(("No symbols defined for member function %q: skipping"):format(name))
		return
	end

	if (not definition.symbols[info.compiler]) then
		print(("No symbols defined for member function %q for this compiler: skipping"):format(name))
		return
	end

	local arguments = get_argument_list(definition.arguments)

	local def = generator.templates.member_function
		:gsub("{{returns}}", definition.returns)
		:gsub("{{name}}", name)
		:gsub("{{classname}}", generator.names.class(class))
		:gsub("{{arguments}}", arguments)
		:gsub("{{symbol}}", definition.symbols[info.compiler])

	cdef(def)

	return name, info.assembly[name]
end

function generator.names.static_member_function(definition, class)
	return (
		generator.templates.static_member_function_name
		:gsub("{{classname}}", generator.names.class(class))
		:gsub("{{name}}", definition.name)
		:gsub("{{type_suffix}}", mangler.get_type_suffix(definition))
	)
end

function generator.defines.static_member_function(info, definition, class)
	local name = generator.names.static_member_function(definition, class)

	if (not definition.symbols) then
		print(("No symbols defined for static member function %q: skipping"):format(name))
		return
	end

	local arguments = table.concat(definition.arguments, ", ")

	local def = generator.templates.static_member_function
		:gsub("{{returns}}", definition.returns)
		:gsub("{{name}}", name)
		:gsub("{{classname}}", generator.names.class(class))
		:gsub("{{arguments}}", arguments)
		:gsub("{{symbol}}", definition.symbols[info.compiler])

	cdef(def)

	return name, info.assembly[name]
end

return generator