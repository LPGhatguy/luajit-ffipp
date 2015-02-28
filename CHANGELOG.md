# FFI++ Changelog

![1.3.0](https://img.shields.io/badge/1.3.0-alpha-orange.svg?style=flat-square)
- FFI++ is now broken in multiple files, this is much cleaner
	- This also means that FFI++ requires init files to be enabled in your Lua path
- Added `version_string` field to core ffipp file
- Probably API compatible with 1.2.0, but maybe not

![1.2.0](https://img.shields.io/badge/1.2.0-latest-brightgreen.svg?style=flat-square)
- Non-member functions no longer break binding generator
- Reference argument support
- Capable of building simple bindings to relatively complex (non-template) codebases

![1.1.0](https://img.shields.io/badge/1.1.0-unsupported-red.svg?style=flat-square)
- Minor runtime fixes
- First version of MSVC+Windows binding generator

![1.0.0](https://img.shields.io/badge/1.0.0-unsupported-red.svg?style=flat-square)
- First release of FFI++