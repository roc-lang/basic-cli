use core::alloc::Layout;

fn main() {
    host::init();
    let size = unsafe { host::roc_main_size() } as usize;
    let layout = Layout::array::<u8>(size).unwrap();

    unsafe {
        let buffer = std::alloc::alloc(layout);

        host::roc_main(buffer);

        let out = host::call_the_closure(buffer);

        // TODO: deallocation currently causes a segfault (probably because layout doesn't match main's size).
        // investigate why this is and then re-enable this, rather than letting the system clean up the memory.
        //
        // std::alloc::dealloc(buffer, layout);

        std::process::exit(out);
    }
}
