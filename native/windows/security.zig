//! MSVC x64 stack-cookie support. Copyright 2026 basic-cli contributors.
//! SPDX-License-Identifier: UPL-1.0
//!
//! The compiler's check helper must preserve every register on success.
//! Initialize the image's cookie before any platform C initializers execute.

const default_cookie: usize = 0x00002b992ddfa232;
export var __security_cookie: usize = default_cookie;
export var __security_cookie_complement: usize = ~default_cookie;

extern fn BCryptGenRandom(?*anyopaque, [*]u8, u32, u32) callconv(.winapi) i32;

fn fail_fast(code: u32) noreturn {
    asm volatile ("int $0x29"
        :
        : [code] "{ecx}" (code),
        : .{ .memory = true });
    unreachable;
}

export fn __security_init_cookie() callconv(.c) void {
    if (__security_cookie != default_cookie and __security_cookie != 0) {
        __security_cookie_complement = ~__security_cookie;
        return;
    }
    var cookie: usize = 0;
    while (cookie == 0 or cookie == default_cookie) {
        if (BCryptGenRandom(null, @ptrCast(&cookie), @sizeOf(usize), 2) != 0) {
            // FAST_FAIL_FATAL_APP_EXIT: never continue with an unseeded cookie.
            fail_fast(7);
        }
        cookie &= 0x0000ffffffffffff;
    }
    __security_cookie = cookie;
    __security_cookie_complement = ~cookie;
}

fn initialize() callconv(.c) c_int {
    __security_init_cookie();
    return 0;
}

export const basic_cli_security_initializer: *const fn () callconv(.c) c_int
    linksection(".CRT$XIAA") = &initialize;

export fn __security_check_cookie() callconv(.naked) void {
    asm volatile (
        \\cmpq __security_cookie(%rip), %rcx
        \\jne 1f
        \\retq
        \\1:
        \\movl $2, %ecx
        \\int $0x29
    );
}

export fn __report_gsfailure(_: usize) callconv(.c) noreturn {
    fail_fast(2); // FAST_FAIL_STACK_COOKIE_CHECK_FAILURE
}

export fn __report_rangecheckfailure() callconv(.c) noreturn {
    fail_fast(8); // FAST_FAIL_RANGE_CHECK_FAILURE
}
