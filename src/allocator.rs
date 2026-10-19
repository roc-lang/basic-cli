//! General allocations on the static Linux host must reuse freed pages rather
//! than repeatedly returning small size classes to musl's mallocng allocator.
//! Roc's generated DefaultAllocators already use Rust's global allocator, so
//! the ABI metadata, alignment handling and typed resource heaps stay intact.
//! Keep glibc diagnostics on System so Valgrind still observes their allocations.
#[cfg(all(target_os = "linux", target_env = "musl"))]
#[global_allocator]
static ALLOCATOR: mimalloc::MiMalloc = mimalloc::MiMalloc;

#[cfg(test)]
mod tests {
    use crate::resources;

    #[test]
    fn roc_callbacks_preserve_alignment_and_reallocated_bytes() {
        let mut host = resources::make_host();
        for alignment in [1, 2, 8, 16, 64, 4096] {
            for length in [0, 1, 31, 608, 1328, 8192] {
                let mut memory = (host.roc_alloc)(&mut host, length, alignment).cast::<u8>();
                assert_eq!(memory.as_ptr() as usize % alignment, 0);
                // The callback contract permits accessing the requested length,
                // including across a move during growth or shrinkage.
                unsafe { memory.as_ptr().write_bytes(0x5a, length) };
                for new_length in [length + 4096, 17, 0] {
                    let preserved = length.min(new_length).min(17);
                    memory = (host.roc_realloc)(
                        &mut host,
                        memory.as_ptr().cast(),
                        new_length,
                        alignment,
                    )
                    .cast();
                    assert_eq!(memory.as_ptr() as usize % alignment, 0);
                    for index in 0..preserved {
                        assert_eq!(unsafe { memory.as_ptr().add(index).read() }, 0x5a);
                    }
                }
                (host.roc_dealloc)(&mut host, memory.as_ptr().cast(), alignment);
            }
        }
        println!("allocator ABI alignment and realloc checks complete");
    }

    // scripts/test_musl_allocator.py traces this exact test on a native Linux
    // musl executable. Exercise the real Roc callback table, including the
    // metadata prefix and typed-handle dispatch used by compiled applications.
    #[cfg(all(target_os = "linux", target_env = "musl"))]
    #[test]
    fn repeated_small_roc_allocations_reuse_pages() {
        use std::hint::black_box;
        let input_size = std::env::var("BASIC_CLI_ALLOC_CHURN_INPUT")
            .map(|size| size.parse::<usize>().unwrap())
            .unwrap_or(960);
        let iterations = 20_000;
        let mut host = resources::make_host();
        let input = (host.roc_alloc)(&mut host, input_size, 8);
        let mut checksum = 0u64;
        for iteration in 0..iterations {
            let marker = iteration as u8;
            let first = (host.roc_alloc)(&mut host, black_box(8), 8).cast::<u8>();
            unsafe { first.as_ptr().write_bytes(marker, 8) };
            let first = (host.roc_realloc)(&mut host, first.as_ptr().cast(), 608, 8).cast::<u8>();
            let second = (host.roc_alloc)(&mut host, black_box(608), 8);
            unsafe { first.as_ptr().add(607).write(marker) };
            let first = (host.roc_realloc)(&mut host, first.as_ptr().cast(), 1328, 8).cast::<u8>();
            let small = (host.roc_alloc)(&mut host, black_box(32), 8);
            assert_eq!(unsafe { black_box(first).as_ptr().read() }, marker);
            checksum += u64::from(unsafe { first.as_ptr().add(607).read() });
            (host.roc_dealloc)(&mut host, small.as_ptr(), 8);
            (host.roc_dealloc)(&mut host, second.as_ptr(), 8);
            (host.roc_dealloc)(&mut host, first.as_ptr().cast(), 8);
        }
        (host.roc_dealloc)(&mut host, input.as_ptr(), 8);
        println!("allocator churn complete: input_size={input_size} iterations={iterations} checksum={checksum}");
    }
}
