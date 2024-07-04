#include <iostream>

// extern "C" void roc_dealloc(void* ptr, uint32_t _alignment);

extern "C" struct RocBox {
  void *inner;
};

extern "C" struct RocStr {
  char *bytes;
  intptr_t len;
  intptr_t cap;
};

extern "C" void say_hi(RocBox b) {
  auto str = *(static_cast<RocStr *>(b.inner));
  std::cout << "Hello from FFI loaded C++!\nRoc sent over FFI:\n";
  char *bytes = str.bytes;
  size_t len = str.len;
  if (str.cap < 0) {
    bytes = static_cast<char *>(b.inner);
    len = bytes[23] & 0x7F;
  }

  std::cout << std::string_view(bytes, len) << std::endl;

  // roc_dealloc(static_cast<size_t*>(b.inner)-1, std::alignment_of<size_t>());
}
