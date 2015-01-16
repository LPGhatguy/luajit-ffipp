#include <string>
#include <iostream>
#include <stdint.h>

/*
This is some really mediocre C++ code to demonstrate building a binding.

Use build.bat/build.sh with GCC, or make a VS project to compile to a DLL.
I'd make a real build script, but it isn't worth it right now.
*/

// For Windows, other platforms usually don't care about it
#define DllExport __declspec(dllexport)

class DllExport HelloClass {
public:
	int64_t one;
	int32_t two;
	double three;

	HelloClass();
	HelloClass(int64_t one, int32_t two);
	HelloClass(int64_t one, int32_t two, double three);

	~HelloClass();

	virtual void SayHello();
	virtual void Say(const char* value);

	static void StaticHello();
private:
	int32_t thisIsPrivate;
};

HelloClass::HelloClass() {
	this->one = 1;
	this->two = 2;
	this->three = 3;
	this->thisIsPrivate = 4;
}
HelloClass::~HelloClass(){}
HelloClass::HelloClass(int64_t one, int32_t two) {
	this->one = one;
	this->two = two;
}
HelloClass::HelloClass(int64_t one, int32_t two, double three) {
	this->one = one;
	this->two = two;
	this->three = three;
}

void HelloClass::SayHello() {
	std::cout << "Hello, from HelloClass with\none: " << one << ", two: " << two << ", and three: " << three << std::endl;
}
void HelloClass::Say(const char* value) {
	std::cout << value << std::endl;
}
void HelloClass::StaticHello() {
	std::cout << "Hello, from HelloClass::StaticHello!" << std::endl;
}