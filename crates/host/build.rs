fn main() {
    #[cfg(not(windows))]
    println!("cargo:rustc-link-lib=dylib=app");

    #[cfg(windows)]
    println!("cargo:rustc-link-lib=dylib=libapp");

    println!("cargo:rustc-link-search=./platform");

    // watch the platform and rebuild app stub it it changes
    println!("cargo::rerun-if-changed=./platform/main.roc");

    // build the app stub dynamic library "libapp"
    let app_stub_path = workspace_dir().join("platform").join("libapp.roc");
    std::process::Command::new("roc")
        .args(&[
            "build",
            "--lib",
            format!("{}", app_stub_path.display()).as_str(),
        ])
        .status()
        .expect("unable to build the app stub dynamic library 'platform/libapp.roc'");

    println!(
        "cargo::warning=SUCCESSFULLY BUILT APP STUB DYNAMIC LIBRARY{:?}",
        app_stub_path
    );
}

/// helper to get the path to the workspace
fn workspace_dir() -> std::path::PathBuf {
    let output = std::process::Command::new(env!("CARGO"))
        .arg("locate-project")
        .arg("--workspace")
        .arg("--message-format=plain")
        .output()
        .unwrap()
        .stdout;
    let cargo_path = std::path::Path::new(std::str::from_utf8(&output).unwrap().trim());
    cargo_path.parent().unwrap().to_path_buf()
}
