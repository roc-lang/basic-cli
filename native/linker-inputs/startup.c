#include <pthread.h>
#include <stdio.h>
static const char *text(void) { return "startup passed"; }
static const char *(*volatile callback)(void) = text;
static _Thread_local int value = 42;
static void *worker(void *unused) {
    (void)unused;
    if (value != 42) return (void *)1;
    value = 99;
    return 0;
}
int main(void) {
    pthread_t thread;
    void *result;
    if (pthread_create(&thread, 0, worker, 0) || pthread_join(thread, &result)) return 1;
    if (result || value != 42) return 2;
    puts(callback());
    return 0;
}
