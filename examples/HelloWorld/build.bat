@echo off
call mingwvars
g++ -shared -static-libgcc -static-libstdc++ -o HelloWorld-gcc.dll HelloWorld.cpp