use roc_env::arg::ArgToAndFromHost;

fn main() {
    let args = std::env::args_os().map(ArgToAndFromHost::from).collect();

    let exit_code = roc_host::rust_main(args);

    std::process::exit(exit_code);
}
