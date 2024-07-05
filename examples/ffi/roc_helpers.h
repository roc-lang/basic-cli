#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <limits>
#include <string_view>

extern "C" void *roc_alloc(size_t size, uint32_t _alignment);
extern "C" void *roc_realloc(void *ptr, size_t new_size, size_t _old_size,
                             uint32_t _alignment);
extern "C" void roc_dealloc(void *ptr, uint32_t _alignment);

extern "C" struct RocBox {
  void *inner;
};

extern "C" struct RocStr {
  char *bytes;
  intptr_t len;
  intptr_t cap;
};

extern "C" struct RocList {
  void *ptr;
  size_t len;
  size_t cap;
};

inline void *allocate_with_refcount(size_t count, size_t elem_size,
                                    size_t elem_align) {
  size_t rc_align = sizeof(size_t);
  size_t alignment = std::max(rc_align, elem_align);

  void *raw_ptr = roc_alloc(elem_size * count + alignment, alignment);
  void *data_ptr = static_cast<char *>(raw_ptr) + alignment;
  void *rc_ptr = static_cast<char *>(data_ptr) - rc_align;

  // Set RC to one value.
  *(static_cast<intptr_t *>(rc_ptr)) = std::numeric_limits<intptr_t>::min();

  return data_ptr;
}

template <typename T> T *allocate_with_refcount(size_t count) {
  void *data_ptr = allocate_with_refcount(count, sizeof(T), alignof(T));
  return static_cast<T *>(data_ptr);
}

template <typename T> RocBox box_data(T t) {
  RocBox out;

  T *data_ptr = allocate_with_refcount<T>(1);
  *data_ptr = t;
  out.inner = data_ptr;
  return out;
}

inline bool roc_str_is_small(const RocStr &str) { return str.cap < 0; }

inline std::string_view roc_str_view(RocStr *str) {
  char *path_bytes = str->bytes;
  size_t path_len = str->len;
  if (str->cap < 0) {
    path_bytes = reinterpret_cast<char *>(str);
    path_len = path_bytes[23] & 0x7F;
  }

  return {path_bytes, path_len};
}

inline void roc_list_ensure_excess_capacity(RocList &list, size_t count,
                                            size_t elem_size,
                                            size_t elem_align) {
  if (!list.ptr) {
    list.ptr = allocate_with_refcount(64, elem_size, elem_align);
    list.len = 0;
    list.cap = 64;
  }
  if (list.cap - list.len < count) {
    std::cerr << "TODO: reallocation of lists" << std::endl;
    exit(-7);
  }
}

template <typename T>
void roc_list_ensure_excess_capacity(RocList &list, size_t count) {
  roc_list_ensure_excess_capacity(list, count, sizeof(T), alignof(T));
}

template <typename T> void roc_list_append(RocList &list, T data) {
  roc_list_ensure_excess_capacity<T>(list, 1);

  reinterpret_cast<T *>(list.ptr)[list.len++] = data;
}
