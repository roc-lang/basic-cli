// Copyright 2026 basic-cli contributors. SPDX-License-Identifier: UPL-1.0
//
// Rust's MSVC SEH TypeDescriptor references the C++ type_info vtable.
// Generate that vtable using the MSVC ABI rather than exporting
// a dummy data symbol. The two data fields match MSVC's type descriptor layout.
// Undecorated names belong to the UCRT's process-wide type-info cache; destroying
// a descriptor does not destroy that cache. Actual exception handling is provided
// by the OS UCRT's __CxxFrameHandler3 import, not by this metadata class.

extern "C" void free(void*);
void operator delete(void* object) noexcept { free(object); }

class type_info {
public:
    type_info() noexcept : undecorated_name(nullptr), decorated_name{0} {}
    virtual ~type_info() noexcept;
    static void operator delete(void* object) noexcept { free(object); }
    static void* operator new(decltype(sizeof(0)), void* storage) noexcept { return storage; }

private:
    const char* undecorated_name;
    char decorated_name[1];
};

type_info::~type_info() noexcept = default;

static_assert(sizeof(type_info) == 3 * sizeof(void*), "MSVC type descriptor layout");

// MSVC emits a class's vtable when a constructor uses it. This also provides a
// constructor for the runtime ABI fixture to check the generated metadata.
extern "C" void basic_cli_construct_type_info(void* storage) noexcept {
    new (storage) type_info;
}
