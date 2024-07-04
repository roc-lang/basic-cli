#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>

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

template <typename T> T *allocate_with_refcount(size_t count) {
  size_t rc_align = sizeof(size_t);
  size_t alignment = std::max(rc_align, alignof(T));

  void *raw_ptr = roc_alloc(sizeof(T) * count + alignment, alignment);
  void *data_ptr = static_cast<char *>(raw_ptr) + alignment;
  void *rc_ptr = static_cast<char *>(data_ptr) - rc_align;

  // Set RC to one value.
  *(static_cast<intptr_t *>(rc_ptr)) = std::numeric_limits<intptr_t>::min();

  return static_cast<T *>(data_ptr);
}

template <typename T> RocBox box_data(T t) {
  RocBox out;

  T *data_ptr = allocate_with_refcount<T>(1);
  *data_ptr = t;
  out.inner = data_ptr;
  return out;
}
