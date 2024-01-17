use core::alloc::Layout;

fn main() {
    host::init();
    let size = unsafe { host::roc_main_size() } as usize;
    let layout = Layout::array::<u8>(size).unwrap();

    unsafe {
        let buffer = std::alloc::alloc(layout);

        host::roc_main(buffer);

        let out = host::call_the_closure(buffer);

        std::alloc::dealloc(buffer, layout);

        std::process::exit(out);
    }
}
