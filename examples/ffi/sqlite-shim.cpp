#include <cstddef>
#include <cstdint>
#include <iostream>
#include <utility>

#include "roc_helpers.h"
#include "vendor/sqlite3.h"

#define MAX_SIZE 256

size_t load_roc_str(RocStr *str, char buf[MAX_SIZE]) {
  auto view = roc_str_view(str);
  if (view.size() >= MAX_SIZE) {
    // should return an error here
    std::cerr << "RocStr length too long: Max length is " << MAX_SIZE - 1
              << std::endl;
    exit(-1);
  }

  for (size_t i = 0; i < view.size(); ++i)
    buf[i] = view[i];
  buf[view.size()] = 0;
  return view.size();
}

// Str -> U64
// path -> pointer to db
extern "C" RocBox open_db(RocBox b) {
  char buf[MAX_SIZE];
  load_roc_str(static_cast<RocStr *>(b.inner), buf);

  sqlite3 *db;
  if (int rc = sqlite3_open(buf, &db)) {
    // should return an error, failure to open db.
    std::cerr << "Sqlite failed to open db: " << sqlite3_errmsg(db)
              << std::endl;
    sqlite3_close(db);
    exit(rc);
  }

  return box_data(reinterpret_cast<uint64_t>(db));
}

// U64 -> {}
// pointer to db to nothing
extern "C" void close_db(RocBox b) {
  auto *db = *static_cast<sqlite3 **>(b.inner);
  if (int rc = sqlite3_close(db)) {
    // should return an error, failure to close db.
    std::cerr << "Sqlite failed to close db: " << sqlite3_errmsg(db)
              << std::endl;
  }
}

// (U64, Str) -> U64
// pointer to db and stmt string to prepared stmt.
extern "C" RocBox prepare_stmt(RocBox b) {
  auto [db, stmt_str] = *static_cast<std::tuple<sqlite3 *, RocStr> *>(b.inner);

  char buf[MAX_SIZE];
  size_t size = load_roc_str(&stmt_str, buf);

  sqlite3_stmt *stmt;
  if (int rc = sqlite3_prepare_v2(db, buf, size + 1, &stmt, nullptr)) {
    // should return an error, failure to prepare stmt.
    std::cerr << "Sqlite failed to prepare stmt: " << sqlite3_errmsg(db)
              << std::endl;
    sqlite3_finalize(stmt);
    exit(rc);
  }

  return box_data(reinterpret_cast<uint64_t>(stmt));
}

extern "C" union SqlValData {
  RocList bytes;
  int64_t integer;
  double real;
  RocStr str;
};

enum SqlValTag {
  bytes = 0,
  integer = 1,
  null = 2,
  real = 3,
  string = 4,
};

extern "C" struct SqlVal {
  SqlValData data;
  uint8_t tag;
};

void bind_params(sqlite3 *db, sqlite3_stmt *stmt, RocList bindings) {
  // Loop through bindings and add them.
  auto binding_ptr = static_cast<std::tuple<RocStr, SqlVal> *>(bindings.ptr);
  for (size_t i = 0; i < bindings.len; ++i) {
    auto [key, val] = binding_ptr[i];

    char buf[MAX_SIZE];
    load_roc_str(&key, buf);
    int param = sqlite3_bind_parameter_index(stmt, buf);
    if (!param) {
      std::cerr << "Sqlite failed to bind param: " << buf << std::endl;
      exit(-2);
    }

    int rc;
    switch (static_cast<SqlValTag>(val.tag)) {
    case bytes: {
      RocList list = val.data.bytes;
      rc = sqlite3_bind_blob64(stmt, param, list.ptr, list.len, SQLITE_STATIC);
      break;
    }
    case integer:
      rc = sqlite3_bind_int64(stmt, param, val.data.integer);
      break;
    case null:
      rc = sqlite3_bind_null(stmt, param);
      break;
    case real:
      rc = sqlite3_bind_double(stmt, param, val.data.real);
      break;
    case string: {
      auto lifetime = SQLITE_STATIC;
      if (roc_str_is_small(val.data.str))
        lifetime = SQLITE_TRANSIENT;

      std::string_view view = roc_str_view(&val.data.str);
      rc = sqlite3_bind_text64(stmt, param, view.data(), view.size(), lifetime,
                               SQLITE_UTF8);
      break;
    }
    }
    if (rc) {
      std::cerr << "Sqlite failed to bind param: " << sqlite3_errmsg(db)
                << std::endl;
      exit(-2);
    }
  }
}

SqlVal load_sqlval(sqlite3_stmt *stmt, int i) {
  SqlVal val{};
  switch (sqlite3_column_type(stmt, i)) {
  case SQLITE_INTEGER:
    val.tag = integer;
    val.data.integer = sqlite3_column_int64(stmt, i);
    break;
  case SQLITE_FLOAT:
    val.tag = real;
    val.data.real = sqlite3_column_double(stmt, i);
    break;
  case SQLITE_TEXT: {
    val.tag = string;
    RocStr &str = val.data.str;
    str.len = sqlite3_column_bytes(stmt, i);
    str.cap = str.len;
    char *data = allocate_with_refcount<char>(str.len);
    const char *text =
        reinterpret_cast<const char *>(sqlite3_column_text(stmt, i));
    for (size_t j = 0; j < str.len; ++j) {
      data[j] = text[j];
    }
    str.bytes = data;
    break;
  }
  case SQLITE_BLOB: {
    val.tag = bytes;
    RocList &list = val.data.bytes;
    list.len = sqlite3_column_bytes(stmt, i);
    list.cap = list.len;
    uint8_t *data = allocate_with_refcount<uint8_t>(list.len);
    const uint8_t *blob =
        reinterpret_cast<const uint8_t *>(sqlite3_column_blob(stmt, i));
    for (size_t j = 0; j < list.len; ++j) {
      data[j] = blob[j];
    }
    list.ptr = data;
    break;
  }
  case SQLITE_NULL:
  default:
    val.tag = null;
    break;
  }
  return val;
}

// (U64, U64, List (Str, SqlVal)) -> List (List SqlVal)
extern "C" RocBox execute_stmt(RocBox b) {
  auto [db, stmt, bindings] =
      *static_cast<std::tuple<sqlite3 *, sqlite3_stmt *, RocList> *>(b.inner);

  bind_params(db, stmt, bindings);
  // Load rows and cols.
  int col_count = sqlite3_column_count(stmt);
  RocList out{nullptr, 0, 0};
  int rc;
  while (true) {
    rc = sqlite3_step(stmt);
    if (rc == SQLITE_DONE)
      break;
    if (rc != SQLITE_ROW) {
      std::cerr << "Sqlite failed during execution: " << sqlite3_errmsg(db)
                << std::endl;
      exit(-3);
    }

    // This would be even more unsafe, but this could do raw writes to build
    // tuples instead of nested lists with more allocations. On the roc side
    // would use the unsafe unboxing to generate a tuple type. The user would be
    // required to pick the correct tuple type. If they get it wrong broken data
    // will be piped through there code. It would be way faster. No allocation
    // per row.
    RocList inner;
    inner.len = col_count;
    inner.cap = col_count;
    inner.ptr = allocate_with_refcount<SqlVal>(inner.len);
    for (int i = 0; i < col_count; ++i) {
      reinterpret_cast<SqlVal *>(inner.ptr)[i] = load_sqlval(stmt, i);
    }

    // Store row list into outer list.
    roc_list_append(out, inner);
  }

  // Reset stmt for next use.
  sqlite3_reset(stmt);
  sqlite3_clear_bindings(stmt);

  return box_data(out);
}

size_t col_roc_type_size(sqlite3_stmt *stmt, int i) {
  switch (sqlite3_column_type(stmt, i)) {
  case SQLITE_INTEGER:
  case SQLITE_FLOAT:
    return 8;
  case SQLITE_TEXT:
  case SQLITE_BLOB:
    return 24;
  case SQLITE_NULL:
  default:
    return 0;
  }
}

void load_raw_val(sqlite3_stmt *stmt, int i, void *out) {
  switch (sqlite3_column_type(stmt, i)) {
  case SQLITE_INTEGER:
    *reinterpret_cast<int64_t *>(out) = sqlite3_column_int64(stmt, i);
    return;
  case SQLITE_FLOAT:
    *reinterpret_cast<double *>(out) = sqlite3_column_double(stmt, i);
    return;
  case SQLITE_TEXT: {
    RocStr *str = reinterpret_cast<RocStr *>(out);
    str->len = sqlite3_column_bytes(stmt, i);
    str->cap = str->len;
    char *data = allocate_with_refcount<char>(str->len);
    const char *text =
        reinterpret_cast<const char *>(sqlite3_column_text(stmt, i));
    for (size_t j = 0; j < str->len; ++j) {
      data[j] = text[j];
    }
    str->bytes = data;
    return;
  }
  case SQLITE_BLOB: {
    RocList *list = reinterpret_cast<RocList *>(out);
    list->len = sqlite3_column_bytes(stmt, i);
    list->cap = list->len;
    uint8_t *data = allocate_with_refcount<uint8_t>(list->len);
    const uint8_t *blob =
        reinterpret_cast<const uint8_t *>(sqlite3_column_blob(stmt, i));
    for (size_t j = 0; j < list->len; ++j) {
      data[j] = blob[j];
    }
    list->ptr = data;
    return;
  }
  case SQLITE_NULL:
  default:
    return;
  }
}

// (U64, U64, List (Str, SqlVal)) -> List (a, b, c, ...)
// This is super unsafe. It will return a different type based on the query.
// That said, it avoids nested lists and should be way faster.
extern "C" RocBox execute_stmt_unsafe_tuple(RocBox b) {
  auto [db, stmt, bindings] =
      *static_cast<std::tuple<sqlite3 *, sqlite3_stmt *, RocList> *>(b.inner);

  bind_params(db, stmt, bindings);
  // Load rows and cols.
  int col_count = sqlite3_column_count(stmt);
  RocList out{nullptr, 0, 0};
  int rc;
  while (true) {
    rc = sqlite3_step(stmt);
    if (rc == SQLITE_DONE)
      break;
    if (rc != SQLITE_ROW) {
      std::cerr << "Sqlite failed during execution: " << sqlite3_errmsg(db)
                << std::endl;
      exit(-3);
    }

    // Technically, I think these types can change between calls. So pretty
    // unsafe. Maybe should make query author pass the info in and then have
    // sqlite convert to specified types...
    size_t row_bytes = 0;
    for (int i = 0; i < col_count; ++i) {
      row_bytes += col_roc_type_size(stmt, i);
    }
    if (row_bytes == 0)
      continue;

    size_t row_align = sizeof(size_t);
    roc_list_ensure_excess_capacity(out, 1, row_bytes, row_align);

    auto row_ptr = reinterpret_cast<uint8_t *>(out.ptr) + (out.len * row_bytes);
    out.len += 1;
    size_t offset = 0;
    for (int i = 0; i < col_count; ++i) {
      load_raw_val(stmt, i, row_ptr + offset);
      offset += col_roc_type_size(stmt, i);
    }
  }

  // Reset stmt for next use.
  sqlite3_reset(stmt);
  sqlite3_clear_bindings(stmt);

  return box_data(out);
}

// (U64, U64) -> {}
// pointer to db and stmt to nothing
extern "C" void finalize_stmt(RocBox b) {
  auto [db, stmt] =
      *static_cast<std::tuple<sqlite3 *, sqlite3_stmt *> *>(b.inner);
  if (int rc = sqlite3_finalize(stmt)) {
    // should return an error, failure to finalize stmt.
    std::cerr << "Sqlite failed to finalize stmt: " << sqlite3_errmsg(db)
              << std::endl;
  }
}
