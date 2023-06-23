#include <stdint.h>

extern int32_t rust_main();

int main() {
  int32_t result = rust_main();
  return (int)result;
}
