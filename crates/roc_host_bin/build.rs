fn main() {
    // Make sure we have enough free space for additional load commands
    // that we expect the surgical linker to add to the preprocessed host.
    #[cfg(target_os = "macos")]
    println!("cargo:rustc-link-arg=-Wl,-headerpad,0x1000")
}
