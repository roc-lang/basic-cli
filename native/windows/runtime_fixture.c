/* Runtime ABI regression fixture. Copyright 2026 basic-cli contributors.
 * SPDX-License-Identifier: UPL-1.0 */
typedef unsigned long long size_t;
extern size_t __security_cookie, __security_cookie_complement;
extern void __security_check_cookie(size_t);
extern void __security_init_cookie(void);
extern void basic_cli_construct_type_info(void *);
__declspec(dllimport) unsigned long __stdcall SetErrorMode(unsigned long);
__declspec(dllimport) void *__stdcall CreateThread(void *, size_t,
    unsigned long (__stdcall *)(void *), void *, unsigned long, unsigned long *);
__declspec(dllimport) unsigned long __stdcall WaitForSingleObject(void *, unsigned long);
__declspec(dllimport) int __stdcall CloseHandle(void *);
__declspec(dllimport) int __stdcall GetExitCodeThread(void *, unsigned long *);

static int initialized;
static int tls_callbacks;
__declspec(thread) static int thread_value = 42;

static void __stdcall on_thread(void *module, unsigned long reason, void *reserved) {
    (void)module; (void)reserved;
    if (reason == 1 || reason == 2) ++tls_callbacks;
}
#pragma section(".CRT$XLB", read)
__declspec(allocate(".CRT$XLB")) void (__stdcall *fixture_tls_callback)(void *, unsigned long, void *) = on_thread;

static int initialize_c(void) {
    if (__security_cookie == 0 || __security_cookie == 0x2b992ddfa232ULL ||
        __security_cookie_complement != ~__security_cookie) return 1;
#ifdef FAIL_INITIALIZER
    return 7;
#else
    initialized = 1;
    return 0;
#endif
}
static void initialize_cpp(void) { if (initialized == 1) initialized = 2; }
#pragma section(".CRT$XIB", read)
#pragma section(".CRT$XCB", read)
__declspec(allocate(".CRT$XIB")) int (*fixture_c_initializer)(void) = initialize_c;
__declspec(allocate(".CRT$XCB")) void (*fixture_cpp_initializer)(void) = initialize_cpp;

static unsigned long __stdcall worker(void *unused) {
    (void)unused;
    if (thread_value != 42) return 1;
    thread_value = 99;
    return 0;
}

int main(int argc, char **argv) {
    SetErrorMode(3); /* Suppress crash dialog for the deliberate fail-fast case. */
    if (argc == 2 && argv[1][0] == 'f') __security_check_cookie(__security_cookie ^ 1);
    if (argc != 2 || argv[1][0] != 'a' || argv[1][1] != ' ' || argv[1][2] != 'b') return 1;
    if (initialized != 2 || tls_callbacks != 1 || thread_value != 42) return 2;
    __security_check_cookie(__security_cookie);
    size_t saved_cookie = __security_cookie;
    __security_cookie_complement = 0;
    __security_init_cookie();
    if (__security_cookie != saved_cookie || __security_cookie_complement != ~saved_cookie) return 7;
    void *thread = CreateThread(0, 0, worker, 0, 0, 0);
    if (!thread || WaitForSingleObject(thread, 10000) != 0) return 3;
    unsigned long thread_result;
    if (!GetExitCodeThread(thread, &thread_result) || thread_result != 0) return 6;
    CloseHandle(thread);
    if (tls_callbacks != 2 || thread_value != 42) return 4;
    size_t descriptor[3] = {0};
    basic_cli_construct_type_info(descriptor);
    if (!descriptor[0] || descriptor[1] || descriptor[2]) return 5;
    /* MSVC's first vtable slot is the deleting destructor; flag zero keeps storage. */
    void **vtable = (void **)descriptor[0];
    ((void *(*)(void *, unsigned int))vtable[0])(descriptor, 0);
    return 37;
}
