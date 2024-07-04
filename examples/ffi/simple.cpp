#include<iostream>

extern "C" void say_hi() {
    std::cout << "Hello from FFI loaded C++!" << std::endl;
}
