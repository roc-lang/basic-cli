#include <cstddef>
#include <cstdint>
#include <iostream>

#include "vendor/sqlite3.h"
#include "roc_helpers.h"

// Str -> U64
// path -> pointer to db
extern "C" RocBox open_db(RocBox b) {
  auto str = *(static_cast<RocStr *>(b.inner));
  char *path_bytes = str.bytes;
  size_t path_len = str.len;
  if (str.cap < 0) {
    path_bytes = static_cast<char *>(b.inner);
    path_len = path_bytes[23] & 0x7F;
  }

  if (path_len >= 256) {
    // should return an error here
    std::cerr << "Sqlite path length too long: Max length is 255" << std::endl;
    exit(-1);
  }

  char bytes[256];
  for (size_t i = 0; i < path_len; ++i)
    bytes[i] = path_bytes[i];
  bytes[path_len] = 0;

  sqlite3 *db;
  if (int rc = sqlite3_open(bytes, &db)) {
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
  auto* db = static_cast<sqlite3 *>(b.inner);
  if(int rc = sqlite3_close(db)) {
    // should return an error, failure to close db.
    std::cerr << "Sqlite failed to close db: " << sqlite3_errmsg(db)
              << std::endl;
  }
}
