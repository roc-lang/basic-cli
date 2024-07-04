use core::alloc::Layout;

fn main() {
    host::init();
    let size = unsafe { host::roc_main_size() } as usize;
    let layout = Layout::array::<u8>(size).unwrap();

    unsafe {
        let buffer = std::alloc::alloc(layout);

        host::roc_main(buffer);

        let out = host::call_the_closure(buffer);

        // TODO: Why does removing this cause a segfault?
        print!("");

        std::process::exit(out);
    }
}
