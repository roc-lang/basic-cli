#include <stdint.h>

extern uint32_t rust_main();

int main() {
  uint32_t result = rust_main();
  return (int)result;
}
