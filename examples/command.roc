app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Cmd

# Different ways to run commands like you do in a terminal.

main! = |_args| {
    # Simplest way to execute a command (prints to your terminal).
    exec_result = Cmd.exec!("echo", ["Hello"])
    match exec_result {
        Ok({}) => {}
        Err(_) => Stdout.line!("Error running echo")
    }

    # To execute and capture the output (stdout and stderr) without inheriting your terminal.
    output_result = Cmd.exec_output!(Cmd.args(Cmd.new("echo"), ["Hi"]))
    match output_result {
        Ok(cmd_output) => Stdout.line!("{stderr_utf8_lossy: \"${cmd_output.stderr_utf8_lossy}\", stdout_utf8: \"${cmd_output.stdout_utf8}\"}")
        Err(_) => Stdout.line!("Error capturing output")
    }

    # To run a command with environment variables.
    env_cmd = Cmd.args(
        Cmd.envs(
            Cmd.env(
                Cmd.clear_envs(Cmd.new("env")),
                "FOO",
                "BAR",
            ),
            [("BAZ", "DUCK"), ("XYZ", "ABC")],
        ),
        ["-v"],
    )
    env_result = Cmd.exec_cmd!(env_cmd)
    match env_result {
        Ok({}) => {}
        Err(_) => Stdout.line!("Error running env")
    }

    # To execute and just get the exit code (prints to your terminal).
    # Prefer using `exec!` or `exec_cmd!`.
    exit_result = Cmd.exec_exit_code!(Cmd.args(Cmd.new("cat"), ["non_existent.txt"]))
    match exit_result {
        Ok(exit_code) => Stdout.line!("Exit code: ${exit_code.to_str()}")
        Err(_) => Stdout.line!("Error getting exit code")
    }

    Ok({})
}
