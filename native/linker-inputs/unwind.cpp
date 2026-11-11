// Exercise exception handling and destructor execution in the producer toolchain.
#include <stdio.h>
static int destroyed;
struct Cleanup { ~Cleanup() { destroyed = 1; } };
int main() {
    try {
        Cleanup cleanup;
        throw 42;
    } catch (int value) {
        if (value == 42 && destroyed) {
            puts("unwind passed");
            return 0;
        }
    }
    return 1;
}
