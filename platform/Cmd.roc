import IOErr exposing [IOErr]

Cmd :: {
    args : List(Str),
    clear_envs : Bool,
    envs : List(Str), # TODO change this to List((Str, Str))
    program : Str,
}.{

    ## Simplest way to execute a command by name with arguments.
    ## Stdin, stdout, and stderr are inherited from the parent process.
    ##
    ## If you want to capture the output, use [exec_output!] instead.
    ##
    ## ```roc
    ## Cmd.exec!("echo", ["hello world"])?
    ## ```
    exec! : Str, List(Str) => Try({}, [ExecFailed({ command : Str, exit_code : I32 }), FailedToGetExitCode({ command : Str, err : IOErr }), ..])
    exec! = |program, arguments| {
        exit_code =
            new(program)
            .args(arguments)
            .exec_exit_code!()?

        if exit_code == 0 {
            Ok({})
        } else {
            command = "${program} ${arguments.join_with(" ")}"
            Err(ExecFailed({ command, exit_code }))
        }
    }

    ## Execute a Cmd (using the builder pattern).
    ## Stdin, stdout, and stderr are inherited from the parent process.
    ##
    ## You should prefer using [exec!] instead, only use this if you want to use [env], [envs] or [clear_envs].
    ## If you want to capture the output, use [exec_output!] instead.
    ##
    ## ```roc
    ## Cmd.new("cargo")
    ##     .arg(["build")
    ##     .env("RUST_BACKTRACE", "1")
    ##     .exec_cmd!()?
    ## ```
    exec_cmd! : Cmd => Try({}, [ExecCmdFailed({ command : Str, exit_code : I32 }), FailedToGetExitCode({ command : Str, err : IOErr }), ..])
    exec_cmd! = |cmd| {
        exit_code = exec_exit_code!(cmd)?
        
        if exit_code == 0 {
            Ok({})
        } else {
            Err(ExecCmdFailed({ command: to_str(cmd), exit_code }))
        }
    }

    ## Execute command and capture stdout and stderr as UTF-8 strings.
    ## Invalid UTF-8 sequences are replaced with the Unicode replacement character.
    ##
    ## Use [exec_output_bytes!] instead if you want to capture the output in the original form as bytes.
    ## [exec_output_bytes!] may also be used for maximum performance, because you may be able to avoid unnecessary UTF-8 conversions.
    ##
    ## ```roc
    ## cmd_output =
    ##     Cmd.new("echo")
    ##         .args(["Hi"])
    ##         .exec_output!()?
    ##
    ## Stdout.line!("Echo output: ${cmd_output.stdout_utf8}")?
    ## ```
    #exec_output! : Cmd => Try(
    #    { stdout_utf8 : Str, stderr_utf8_lossy : Str },
    #    [
    #        StdoutContainsInvalidUtf8({ cmd_str : Str, err : [BadUtf8 { index : U64, problem : Str.Utf8Problem }] }),
    #        NonZeroExitCode({ command : Str, exit_code : I32, stdout_utf8_lossy : Str, stderr_utf8_lossy : Str }),
    #        FailedToGetExitCode({ command : Str, err : IOErr }),
    #        ..
    #    ]
    #)
    #exec_output! = |cmd|
    #    exec_try = CmdInternal.command_exec_output!(cmd)

    #   match exec_try {
    #        Ok({ stderr_bytes, stdout_bytes }) =>
    #            stdout_utf8 =
    #                Str.from_utf8(stdout_bytes)
    #                    .map_err(|err| StdoutContainsInvalidUtf8({ cmd_str: to_str(cmd), err }))?

    #            stderr_utf8_lossy = Str.from_utf8_lossy(stderr_bytes)

    #            Ok({ stdout_utf8, stderr_utf8_lossy })

    #        Err(inside_try) =>
    #            match inside_try {
    #                Ok({ exit_code, stderr_bytes, stdout_bytes }) =>
    #                    stdout_utf8_lossy = Str.from_utf8_lossy(stdout_bytes)
    #                    stderr_utf8_lossy = Str.from_utf8_lossy(stderr_bytes)

    #                    Err(NonZeroExitCode({ command: to_str(cmd), exit_code, stdout_utf8_lossy, stderr_utf8_lossy }))

    #                Err(err) =>
    #                    Err(FailedToGetExitCode({ command: to_str(cmd), err: InternalIOErr.handle_err(err) }))
    #            }
    #    }

    ## Execute command and capture stdout and stderr in the original form as bytes.
    ##
    ## Use [exec_output!] instead if you want to get the output as UTF-8 strings.
    ##
    ## ```roc
    ## cmd_output =
    ##     Cmd.new("echo")
    ##         .args(["Hi"])
    ##         .exec_output_bytes!()?
    ##
    ## Stdout.line!("${Str.inspect(cmd_output_bytes)}")? # {stderr_bytes: [], stdout_bytes: [72, 105, 10]}
    ## ```
    #exec_output_bytes! : Cmd => Try(
    #    { stderr_bytes : List(U8), stdout_bytes : List(U8) }
    #    [
    #        FailedToGetExitCodeB(IOErr), # TODO: perhaps no need for B?
    #        NonZeroExitCode({ exit_code : I32, stderr_bytes : List(U8), stdout_bytes : List(U8) }),
    #        ..
    #    ]
    #)
    #exec_output_bytes! = |cmd| {
    #    exec_try = CmdInternal.command_exec_output!(cmd) # TODO

    #    match exec_try {
    #        Ok({ stderr_bytes, stdout_bytes }) =>
    #            Ok({ stdout_bytes, stderr_bytes })

    #        Err(inside_try) =>
    #            match inside_try {
    #                Ok({ exit_code, stderr_bytes, stdout_bytes }) ->
    #                    Err(NonZeroExitCodeB({ exit_code, stdout_bytes, stderr_bytes }))

    #                Err(err) ->
    #                    Err(FailedToGetExitCodeB(InternalIOErr.handle_err(err)))
    #            }
    #    }
    #}

    ## Execute a command and return its exit code.
    ## Stdin, stdout, and stderr are inherited from the parent process.
    ##
    ## You should prefer using [exec!] or [exec_cmd!] instead, only use this if you want to take a specific action based on a **specific non-zero exit code**.
    ## For example, `roc check` returns exit code 1 if there are errors, and exit code 2 if there are only warnings.
    ## So, you could use `exec_exit_code!` to ignore warnings on `roc check`.
    ##
    ## ```roc
    ## exit_code = Cmd.new("cat").arg("non_existent.txt").exec_exit_code!()?
    ## ```
    exec_exit_code! : Cmd => Try(I32, [FailedToGetExitCode({ command : Str, err : IOErr }), ..])
    exec_exit_code! = |cmd| {
        match host_exec_exit_code!(cmd) {
            Ok(num) => Ok(num)
            Err(io_err) => Err(FailedToGetExitCode({ command : to_str(cmd), err: io_err }))
        }
    }

    ## Create a new command with the given program name. Use a function that starts with `exec_` to execute it.
    ##
    ## ```roc
    ## cmd = Cmd.new("ls")
    ## ```
    new : Str -> Cmd
    new = |program| {
        args: [],
        clear_envs: Bool.False,
        envs: [],
        program,
    }

    ## Add a single argument to the command.
    ## ❗ Shell features like variable subsitition (e.g. `$FOO`), glob patterns (e.g. `*.txt`), ... are not available.
    ##
    ## ```roc
    ## cmd = Cmd.new("ls").arg("-l")
    ## ```
    arg : Cmd, Str -> Cmd
    arg = |cmd, a| {
        ..cmd,
        args: cmd.args.append(a),
    }

    ## Add multiple arguments to the command.
    ## ❗ Shell features like variable subsitition (e.g. `$FOO`), glob patterns (e.g. `*.txt`), ... are not available.
    ##
    ## ```roc
    ## cmd = Cmd.new("ls").args(["-l", "-a"])
    ## ```
    args : Cmd, List(Str) -> Cmd
    args = |cmd, new_args| {
        ..cmd,
        args: cmd.args.concat(new_args),
    }

    ## Add a single environment variable to the command.
    ## 
    ##
    ## ```roc
    ## cmd = Cmd.new("env").env("FOO", "bar") # add the environment variable "FOO" with value "bar"
    ## ```
    env : Cmd, Str, Str -> Cmd
    env = |cmd, key, value| {
        ..cmd,
        envs: cmd.envs.concat([key, value]),
    }

    ## Add multiple environment variables to the command.
    ##
    ## ```roc
    ## cmd = Cmd.new("env").envs([("FOO", "bar"), ("BAZ", "qux")])
    ## ```
    envs : Cmd, List((Str, Str)) -> Cmd
    envs = |cmd, pairs| {
        flat = pairs.fold([], |acc, (k, v)| acc.concat([k, v]))
        {
            ..cmd,
            envs: cmd.envs.concat(flat),
        }
    }

    ## Clear all environment variables before running the command.
    ## Only environment variables added via `env` or `envs` will be available.
    ## Useful if you want a clean command run that does not behave unexpectedly if the user has some env var set. 
    ##
    ## ```roc
    ## cmd =
    ##     Cmd.new("env")
    ##         .clear_envs()
    ##         .env("ONLY_THIS", "visible")
    ## ```
    clear_envs : Cmd -> Cmd
    clear_envs = |cmd| {
        args: cmd.args,
        clear_envs: Bool.True,
        envs: cmd.envs,
        program: cmd.program,
    }
}

host_exec_exit_code! : Cmd => Try(I32, IOErr)

to_str : Cmd -> Str
to_str = |cmd| {
    my_trim = |trimmed_str| {if trimmed_str.is_empty() "" else "envs: ${trimmed_str}"}

    envs_str =
        cmd.envs
            # TODO once we're using List of tuples: .map(|(key, value)| "${key}=${value}")
            .join_with(" ")
            .trim()->my_trim()

    clear_envs_str = if cmd.clear_envs ", clear_envs: true" else ""
    
    \\{ cmd: ${cmd.program}, args: ${Str.join_with(cmd.args, " ")}${envs_str}${clear_envs_str} }
}

# Do not change the order of the fields! It will lead to a segfault.
OutputFromHostSuccess : {
    stderr_bytes : List(U8),
    stdout_bytes : List(U8),
}

# Do not change the order of the fields! It will lead to a segfault.
OutputFromHostFailure : {
    stderr_bytes : List(U8),
    stdout_bytes : List(U8),
    exit_code : I32,
}
