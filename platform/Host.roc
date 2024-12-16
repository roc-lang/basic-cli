hosted Host
    exposes [
        TcpStream,
        FileReader,
        InternalIOErr,
        args!,
        dir_list!,
        dir_create!,
        dir_create_all!,
        dir_delete_empty!,
        dir_delete_all!,
        hard_link!,
        env_dict!,
        env_var!,
        cwd!,
        set_cwd!,
        exe_path!,
        stdout_line!,
        stdout_write!,
        stderr_line!,
        stderr_write!,
        stdin_line!,
        stdin_bytes!,
        stdin_read_to_end!,
        tty_mode_canonical!,
        tty_mode_raw!,
        send_request!,
        file_read_bytes!,
        file_delete!,
        file_write_utf8!,
        file_write_bytes!,
        file_reader!,
        file_read_line!,
        path_type!,
        posix_time!,
        tcp_connect!,
        tcp_read_up_to!,
        tcp_read_exactly!,
        tcp_read_until!,
        tcp_write!,
        sleep_millis!,
        command_status!,
        command_output!,
        current_arch_os!,
        temp_dir!,
        get_locale!,
        get_locales!,
    ]
    imports []

import InternalHttp
import InternalCommand
import InternalPath

InternalIOErr : {
    tag : [
        EndOfFile,
        NotFound,
        PermissionDenied,
        BrokenPipe,
        AlreadyExists,
        Interrupted,
        Unsupported,
        OutOfMemory,
        Other,
    ],
    msg : Str,
}

# COMMAND
command_status! : Box InternalCommand.Command => Result {} (List U8)
command_output! : Box InternalCommand.Command => InternalCommand.Output

# FILE
file_write_bytes! : List U8, List U8 => Result {} InternalIOErr
file_write_utf8! : List U8, Str => Result {} InternalIOErr
file_delete! : List U8 => Result {} InternalIOErr
file_read_bytes! : List U8 => Result (List U8) InternalIOErr

FileReader := Box {}
file_reader! : List U8, U64 => Result FileReader InternalIOErr
file_read_line! : FileReader => Result (List U8) InternalIOErr

dir_list! : List U8 => Result (List (List U8)) InternalIOErr
dir_create! : List U8 => Result {} InternalIOErr
dir_create_all! : List U8 => Result {} InternalIOErr
dir_delete_empty! : List U8 => Result {} InternalIOErr
dir_delete_all! : List U8 => Result {} InternalIOErr

hard_link! : List U8 => Result {} InternalIOErr
path_type! : List U8 => Result InternalPath.InternalPathType InternalIOErr
cwd! : {} => Result (List U8) {}
temp_dir! : {} => List U8

# STDIO
stdout_line! : Str => Result {} InternalIOErr
stdout_write! : Str => Result {} InternalIOErr
stderr_line! : Str => Result {} InternalIOErr
stderr_write! : Str => Result {} InternalIOErr
stdin_line! : {} => Result Str InternalIOErr
stdin_bytes! : {} => Result (List U8) InternalIOErr
stdin_read_to_end! : {} => Result (List U8) InternalIOErr

# TCP
send_request! : InternalHttp.RequestToAndFromHost => InternalHttp.ResponseToAndFromHost

TcpStream := Box {}
tcp_connect! : Str, U16 => Result TcpStream Str
tcp_read_up_to! : TcpStream, U64 => Result (List U8) Str
tcp_read_exactly! : TcpStream, U64 => Result (List U8) Str
tcp_read_until! : TcpStream, U8 => Result (List U8) Str
tcp_write! : TcpStream, List U8 => Result {} Str

# OTHERS
current_arch_os! : {} => { arch : Str, os : Str }

get_locale! : {} => Result Str {}
get_locales! : {} => List Str

posix_time! : {} => U128 # TODO why is this a U128 but then getting converted to a I128 in Utc.roc?

sleep_millis! : U64 => {}

tty_mode_canonical! : {} => {}
tty_mode_raw! : {} => {}

env_dict! : {} => List (Str, Str)
env_var! : Str => Result Str {}
exe_path! : {} => Result (List U8) {}
set_cwd! : List U8 => Result {} {}

# If we encounter a Unicode error in any of the args, it will be replaced with
# the Unicode replacement char where necessary.
args! : {} => List Str
