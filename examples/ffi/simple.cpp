#include <string>

#include "roc_helpers.h"

// Roc passes the box in without ownership.
// This means roc frees it for us!!!
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
  msg.bytes = allocate_with_refcount<char>(msg.len);

  for (size_t i = 0; i < base.size(); ++i) {
    msg.bytes[i] = base[i];
  }
  for (size_t i = 0; i < input_len; ++i) {
    msg.bytes[base.size() + i] = input_bytes[i];
  }

  return box_data(msg);
}
