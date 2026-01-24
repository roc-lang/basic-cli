Cmd :: {
    args : List(Str),
    clear_envs : Bool,
    envs : List(Str),
    program : Str,
}.{
    IOErr := [NotFound, PermissionDenied, BrokenPipe, AlreadyExists, Interrupted, Unsupported, OutOfMemory, Other(Str)]

    ## Create a new command with the given program name.
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
    ##
    ## ```roc
    ## cmd = Cmd.new("ls").arg("-l")
    ## ```
    arg : Cmd, Str -> Cmd
    arg = |cmd, a| {
        args: List.append(cmd.args, a),
        clear_envs: cmd.clear_envs,
        envs: cmd.envs,
        program: cmd.program,
    }

    ## Add multiple arguments to the command.
    ##
    ## ```roc
    ## cmd = Cmd.new("ls").args(["-l", "-a"])
    ## ```
    args : Cmd, List(Str) -> Cmd
    args = |cmd, new_args| {
        args: List.concat(cmd.args, new_args),
        clear_envs: cmd.clear_envs,
        envs: cmd.envs,
        program: cmd.program,
    }

    ## Add a single environment variable to the command.
    ##
    ## ```roc
    ## cmd = Cmd.new("env").env("FOO", "bar")
    ## ```
    env : Cmd, Str, Str -> Cmd
    env = |cmd, key, value| {
        args: cmd.args,
        clear_envs: cmd.clear_envs,
        envs: List.concat(cmd.envs, [key, value]),
        program: cmd.program,
    }

    ## Add multiple environment variables to the command.
    ##
    ## ```roc
    ## cmd = Cmd.new("env").envs([("FOO", "bar"), ("BAZ", "qux")])
    ## ```
    envs : Cmd, List((Str, Str)) -> Cmd
    envs = |cmd, pairs| {
        flat = List.fold(pairs, [], |acc, (k, v)| List.concat(acc, [k, v]))
        {
            args: cmd.args,
            clear_envs: cmd.clear_envs,
            envs: List.concat(cmd.envs, flat),
            program: cmd.program,
        }
    }

    ## Clear all environment variables before running the command.
    ## Only environment variables added via `env` or `envs` will be available.
    ##
    ## ```roc
    ## cmd = Cmd.new("env").clear_envs().env("ONLY_THIS", "visible")
    ## ```
    clear_envs : Cmd -> Cmd
    clear_envs = |cmd| {
        args: cmd.args,
        clear_envs: Bool.True,
        envs: cmd.envs,
        program: cmd.program,
    }

    ## Execute a command and return its exit code.
    ## Stdin, stdout, and stderr are inherited from the parent process.
    ##
    ## ```roc
    ## exit_code = Cmd.new("ls").arg("-l").exec_exit_code!()?
    ## ```
    exec_exit_code! : Cmd => Try(I32, [CmdErr(IOErr)])

    ## Execute command and capture stdout/stderr as UTF-8 strings.
    ## Invalid UTF-8 sequences are replaced with the Unicode replacement character.
    ##
    ## ```roc
    ## cmd_output =
    ##     Cmd.new("echo")
    ##     .args(["Hi"])
    ##     .exec_output!()?
    ##
    ## Stdout.line!("Echo output: ${cmd_output.stdout_utf8}")?
    ## ```
    exec_output! : Cmd => Try(
        { stdout_utf8 : Str, stderr_utf8_lossy : Str },
        [CmdErr(IOErr), NonZeroExit({ exit_code : I32, stdout_utf8_lossy : Str, stderr_utf8_lossy : Str })]
    )

    ## Simple helper to execute a command by name with arguments.
    ## Stdin, stdout, and stderr are inherited from the parent process.
    ## Returns Ok if the command exits with code 0.
    ##
    ## ```roc
    ## Cmd.exec!("ls", ["-l", "-a"])?
    ## ```
    exec! : Str, List(Str) => Try({}, [CmdErr(IOErr), ExecFailed({ command : Str, exit_code : I32 })])
    exec! = |program, arguments| {
        cmd = new(program).args(arguments)
        result = exec_exit_code!(cmd)
        match result {
            Ok(0) => Ok({}),
            Ok(exit_code) => Err(ExecFailed({ command: program, exit_code })),
            Err(CmdErr(io_err)) => Err(CmdErr(io_err)),
        }
    }

    ## Execute a command using the builder pattern.
    ## Stdin, stdout, and stderr are inherited from the parent process.
    ## Returns Ok if the command exits with code 0.
    ##
    ## ```roc
    ## Cmd.new("ls").args(["-l", "-a"]).exec_cmd!()?
    ## ```
    exec_cmd! : Cmd => Try({}, [CmdErr(IOErr), ExecFailed({ exit_code : I32 })])
    exec_cmd! = |cmd| {
        result = exec_exit_code!(cmd)
        match result {
            Ok(0) => Ok({}),
            Ok(code) => Err(ExecFailed({ exit_code: code })),
            Err(CmdErr(io_err)) => Err(CmdErr(io_err)),
        }
    }
}
