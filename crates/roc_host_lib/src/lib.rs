use roc_env::arg::ArgToAndFromHost;

/// # Safety
/// This function is the entry point for the program, it will be linked by roc using the legacy linker
/// to produce the final executable.
///
/// Note we use argc and argv to pass arguments to the program instead of std::env::args().
#[no_mangle]
pub unsafe extern "C" fn main(argc: usize, argv: *const *const i8) -> i32 {
    let args = std::slice::from_raw_parts(argv, argc)
        .iter()
        .map(|&c_ptr| {
            let c_str = std::ffi::CStr::from_ptr(c_ptr);

            // TODO confirm this is ok... feels dangerous
            let os_str =
                std::ffi::OsString::from_encoded_bytes_unchecked(c_str.to_bytes().to_owned());

            ArgToAndFromHost::from(os_str)
        })
        .collect();

    // return exit_code
    roc_host::rust_main(args)
}
