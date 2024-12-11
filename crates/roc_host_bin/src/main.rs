use roc_std::{ReadOnlyRocList, ReadOnlyRocStr, RocList, RocStr};
use std::borrow::Borrow;

fn main() {
    let mut args: RocList<ReadOnlyRocStr> = std::env::args_os()
        .map(|os_str| {
            let roc_str = RocStr::from(os_str.to_string_lossy().borrow());
            ReadOnlyRocStr::from(roc_str)
        })
        .collect();
    unsafe { args.set_readonly() };
    std::process::exit(roc_host::rust_main(ReadOnlyRocList::from(args)));
}
