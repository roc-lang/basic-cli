use roc_std::{RocList, RocStr, ReadOnlyRocList, ReadOnlyRocStr};
use std::borrow::Borrow;

#[no_mangle]
pub unsafe extern "C" fn main(argc: usize, argv: *const *const i8) -> i32 {
    let args = std::slice::from_raw_parts(argv, argc);

    let mut args: RocList<ReadOnlyRocStr> = args
        .into_iter()
        .map(|&c_ptr| {
            let c_str = std::ffi::CStr::from_ptr(c_ptr);
            let roc_str = RocStr::from(c_str.to_string_lossy().borrow());
            ReadOnlyRocStr::from(roc_str)
        })
        .collect();
    args.set_readonly();
    roc_host::rust_main(ReadOnlyRocList::from(args))
}
