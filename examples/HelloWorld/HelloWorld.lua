#!/usr/bin/luajit

-- Add FFI++ to the path; used for running this script as-is
package.path = package.path .. ";../../?.lua"

local ffi = require("ffi") -- C FFI
local ffipp = require("ffipp") -- C++ FFI

-- Load a binding and retrieve the table of defined symbols
local binding = ffipp.loadfile("HelloWorld.ffipp")

-- Print off a list of symbols defined by the binding
print("Symbols exposed by binding:")
for name, value in pairs(binding) do
	print(name)
end

-- Call a static function
binding.HelloClass__StaticHello_V()

-- Create a class instance and do things with it
local myhello = ffi.new("HelloClass[1]")
binding.HelloClass__C_LID(myhello, 1, 2, 3)

print(myhello[0].one) --> 1LL
print(myhello[0].two) --> 2
print(myhello[0].three) --> 3

-- Call a member function
binding.HelloClass__SayHello_V(myhello)