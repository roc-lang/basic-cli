#include <limits>
#include <string>

extern "C" void *roc_alloc(size_t size, uint32_t _alignment);
extern "C" void roc_dealloc(void *ptr, uint32_t _alignment);

extern "C" struct RocBox {
  void *inner;
};

extern "C" struct RocStr {
  char *bytes;
  intptr_t len;
  intptr_t cap;
};

extern "C" RocBox say_hi(RocBox b) {
  auto str = *(static_cast<RocStr *>(b.inner));
  char *input_bytes = str.bytes;
  size_t input_len = str.len;
  if (str.cap < 0) {
    input_bytes = static_cast<char *>(b.inner);
    input_len = input_bytes[23] & 0x7F;
  }

  std::string base = "Hello from FFI loaded C++!\nRoc sent over FFI:\n\t";

  RocStr msg;
  msg.len = base.size() + input_len;
  msg.cap = msg.len;
  void *raw_ptr = roc_alloc(msg.len + 8, std::alignment_of<size_t>());
  msg.bytes = static_cast<char *>(raw_ptr) + 8;

  // Set RC
  *(static_cast<intptr_t *>(raw_ptr)) = std::numeric_limits<intptr_t>::min();

  for (size_t i = 0; i < base.size(); ++i) {
    msg.bytes[i] = base[i];
  }
  for (size_t i = 0; i < input_len; ++i) {
    msg.bytes[base.size() + i] = input_bytes[i];
  }
  RocBox out;
  raw_ptr = roc_alloc(sizeof(RocStr) + 8, std::alignment_of<size_t>());
  // Set RC
  *(static_cast<intptr_t *>(raw_ptr)) = std::numeric_limits<intptr_t>::min();
  // Set String
  *reinterpret_cast<RocStr *>(static_cast<intptr_t *>(raw_ptr) + 1) = msg;
  out.inner = static_cast<void *>(static_cast<intptr_t *>(raw_ptr) + 1);

  // TODO: Refcounting and real inner string freeing.
  roc_dealloc(static_cast<size_t *>(b.inner) - 1, std::alignment_of<size_t>());

  return out;
}
