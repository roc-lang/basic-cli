module [
    Command,
    Output,
    OutputFromHost,
    from_host_output,
]

import InternalIOErr

Command : {
    program : Str,
    args : List Str, # [arg0, arg1, arg2, arg3, ...]
    envs : List Str, # [key0, value0, key1, value1, key2, value2, ...]
    clear_envs : Bool,
}

Output : {
    status : Result I32 InternalIOErr.IOErr,
    stdout : List U8,
    stderr : List U8,
}

# This hits a compiler bug: Alias `6.IdentId(11)` not registered in delayed aliases! ...
# output_to_str : Output -> Result Str [BadUtf8 { index : U64, problem : Str.Utf8Problem }]
# output_to_str = |cmd_output|
#     stdout_utf8 = Str.from_utf8(cmd_output.stdout)?
#     stderr_utf8 = Str.from_utf8_lossy(cmd_output.stderr)

#     Ok(
#         output_str_template(cmd_output.status, stdout_utf8, stderr_utf8)
#     )

# output_to_str_lossy : Output -> Str
# output_to_str_lossy = |cmd_output|
#     stdout_utf8 = Str.from_utf8_lossy(cmd_output.stdout)
#     stderr_utf8 = Str.from_utf8_lossy(cmd_output.stderr)

    
#     output_str_template(cmd_output.status, stdout_utf8, stderr_utf8)

# output_str_template : Result I32 InternalIOErr.IOErr, Str, Str -> Str
# output_str_template = |status, stdout_utf8, stderr_utf8|
#     """
#     Output {
#         status: ${Inspect.to_str(status)}
#         stdout: ${stdout_utf8}
#         stderr: ${stderr_utf8}
#     }
#     """
    
from_host_output : OutputFromHost -> Output
from_host_output = |{ status, stdout, stderr }| {
    status: Result.map_err(status, InternalIOErr.handle_err),
    stdout,
    stderr,
}

OutputFromHost : {
    status : Result I32 InternalIOErr.IOErrFromHost,
    stdout : List U8,
    stderr : List U8,
}
