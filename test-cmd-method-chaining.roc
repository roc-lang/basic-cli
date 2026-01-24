app [main!] { pf: platform "./platform/main.roc" }

import pf.Cmd
import pf.Stdout

main! = |_args| {
    # Test method chaining with static dispatch (. syntax)
    _cmd1 = Cmd.new("ls").arg("-l").args(["-a", "-h"])

    # Test multiline
    _cmd2 =
        Cmd.new("env")
        .clear_envs()
        .env("FOO", "bar")
        .envs([("BAZ", "qux")])

    # Test with effects
    Stdout.line!("Testing Cmd method chaining...")

    # Execute a simple command
    cmd = Cmd.new("echo").args(["Hello"])
    exit_result = cmd.exec_exit_code!()
    match exit_result {
        Ok(exit_code) => Stdout.line!("Exit code: ${exit_code.to_str()}")
        Err(_) => Stdout.line!("Error running command")
    }

    Ok({})
}
