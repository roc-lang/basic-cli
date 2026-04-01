app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Cmd

# Tests all error cases in Cmd functions.

main! = |_args| {

    # exec!
    expect_err(
        Cmd.exec!("blablaXYZ", []),
        "Err(FailedToGetExitCode({ command: \"{ cmd: blablaXYZ, args:  }\", err: NotFound }))"
    )?

    expect_err(
        Cmd.exec!("cat", ["non_existent.txt"]),
        "Err(ExecFailed({ command: \"cat non_existent.txt\", exit_code: 1 }))"
    )?

    # exec_cmd!
    expect_err(
        Cmd.new("blablaXYZ").exec_cmd!(),
        "Err(FailedToGetExitCode({ command: \"{ cmd: blablaXYZ, args:  }\", err: NotFound }))"
    )?

    expect_err(
        Cmd.new("cat").arg("non_existent.txt").exec_cmd!(),
        "Err(ExecCmdFailed({ command: \"{ cmd: cat, args: non_existent.txt }\", exit_code: 1 }))"
    )?

    # exec_output!
    expect_err(
        Cmd.new("blablaXYZ").exec_output!(),
        "Err(FailedToGetExitCode({ command: \"{ cmd: blablaXYZ, args:  }\", err: NotFound }))"
    )?

    expect_err(
        Cmd.new("cat").arg("non_existent.txt").exec_output!(),
        "Err(NonZeroExitCode({ command: \"{ cmd: cat, args: non_existent.txt }\", exit_code: 1, stderr_utf8_lossy: \"cat: non_existent.txt: No such file or directory\n\", stdout_utf8_lossy: \"\" }))"
    )?

    # Test StdoutContainsInvalidUtf8 - blocked by compiler bug
    expect_err(
        Cmd.new("printf").args(["\\377\\376"]).exec_output!(),
        "Err(StdoutContainsInvalidUtf8({ cmd_str: \"{ cmd: printf, args: \\\\377\\\\376 }\", err: BadUtf8({ index: 0, problem: InvalidStartByte }) }))"
    )?

    # exec_output_bytes!
    expect_err(
        Cmd.new("blablaXYZ").exec_output_bytes!(),
        "Err(FailedToGetExitCodeB(NotFound))"
    )?

    expect_err(
        Cmd.new("cat").arg("non_existent.txt").exec_output_bytes!(),
        "Err(NonZeroExitCodeB({ exit_code: 1, stderr_bytes: [99, 97, 116, 58, 32, 110, 111, 110, 95, 101, 120, 105, 115, 116, 101, 110, 116, 46, 116, 120, 116, 58, 32, 78, 111, 32, 115, 117, 99, 104, 32, 102, 105, 108, 101, 32, 111, 114, 32, 100, 105, 114, 101, 99, 116, 111, 114, 121, 10], stdout_bytes: [] }))"
    )?

    # exec_exit_code!
    expect_err(
        Cmd.new("blablaXYZ").exec_exit_code!(),
        "Err(FailedToGetExitCode({ command: \"{ cmd: blablaXYZ, args:  }\", err: NotFound }))"
    )?

    # exec_exit_code! with non-zero exit code is not an error - it returns the exit code
    exit_code =
        Cmd.new("cat")
            .arg("non_existent.txt")
            .exec_exit_code!()?

    if exit_code == 1 {
        Ok({})?
    } else {
        Err(FailedExpectation(
            \\- Expected:
            \\1
            \\
            \\- Got:
            \\${Str.inspect(exit_code)}
        ))?
    }

    Stdout.line!("All tests passed.")?

    Ok({})
}

expect_err = |err, expected_str| {
    if Str.inspect(err) == expected_str {
        Ok({})
    } else {
        Err(FailedExpectation(
            \\- Expected:
            \\${expected_str}

            \\- Got:
            \\${Str.inspect(err)}
        ))
    }
}