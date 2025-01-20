hosted Host
    exposes [
        TcpStream,
        FileReader,
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
        sqlite_prepare!,
        sqlite_bind!,
        sqlite_columns!,
        sqlite_column_value!,
        sqlite_step!,
        sqlite_reset!,
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
import InternalCmd
import InternalPath
import InternalIOErr
import InternalSqlite

# COMMAND
command_status! : InternalCmd.Command => Result I32 InternalIOErr.IOErrFromHost
command_output! : InternalCmd.Command => InternalCmd.OutputFromHost

# FILE
file_write_bytes! : List U8, List U8 => Result {} InternalIOErr.IOErrFromHost
file_write_utf8! : List U8, Str => Result {} InternalIOErr.IOErrFromHost
file_delete! : List U8 => Result {} InternalIOErr.IOErrFromHost
file_read_bytes! : List U8 => Result (List U8) InternalIOErr.IOErrFromHost

FileReader := Box {}
file_reader! : List U8, U64 => Result FileReader InternalIOErr.IOErrFromHost
file_read_line! : FileReader => Result (List U8) InternalIOErr.IOErrFromHost

dir_list! : List U8 => Result (List (List U8)) InternalIOErr.IOErrFromHost
dir_create! : List U8 => Result {} InternalIOErr.IOErrFromHost
dir_create_all! : List U8 => Result {} InternalIOErr.IOErrFromHost
dir_delete_empty! : List U8 => Result {} InternalIOErr.IOErrFromHost
dir_delete_all! : List U8 => Result {} InternalIOErr.IOErrFromHost

hard_link! : List U8 => Result {} InternalIOErr.IOErrFromHost
path_type! : List U8 => Result InternalPath.InternalPathType InternalIOErr.IOErrFromHost
cwd! : () => Result (List U8) {}
temp_dir! : () => List U8

# STDIO
stdout_line! : Str => Result {} InternalIOErr.IOErrFromHost
stdout_write! : Str => Result {} InternalIOErr.IOErrFromHost
stderr_line! : Str => Result {} InternalIOErr.IOErrFromHost
stderr_write! : Str => Result {} InternalIOErr.IOErrFromHost
stdin_line! : () => Result Str InternalIOErr.IOErrFromHost
stdin_bytes! : () => Result (List U8) InternalIOErr.IOErrFromHost
stdin_read_to_end! : () => Result (List U8) InternalIOErr.IOErrFromHost

# TCP
send_request! : InternalHttp.RequestToAndFromHost => InternalHttp.ResponseToAndFromHost

TcpStream := Box {}
tcp_connect! : Str, U16 => Result TcpStream Str
tcp_read_up_to! : TcpStream, U64 => Result (List U8) Str
tcp_read_exactly! : TcpStream, U64 => Result (List U8) Str
tcp_read_until! : TcpStream, U8 => Result (List U8) Str
tcp_write! : TcpStream, List U8 => Result {} Str

# SQLITE
sqlite_prepare! : Str, Str => Result (Box {}) InternalSqlite.SqliteError
sqlite_bind! : Box {}, List InternalSqlite.SqliteBindings => Result {} InternalSqlite.SqliteError
sqlite_columns! : Box () => List Str
sqlite_column_value! : Box {}, U64 => Result InternalSqlite.SqliteValue InternalSqlite.SqliteError
sqlite_step! : Box () => Result InternalSqlite.SqliteState InternalSqlite.SqliteError
sqlite_reset! : Box () => Result {} InternalSqlite.SqliteError

# OTHERS
current_arch_os! : () => { arch : Str, os : Str }

get_locale! : () => Result Str {}
get_locales! : () => List Str

posix_time! : () => U128 # TODO why is this a U128 but then getting converted to a I128 in Utc.roc?

sleep_millis! : U64 => {}

tty_mode_canonical! : () => {}
tty_mode_raw! : () => {}

env_dict! : () => List (Str, Str)
env_var! : Str => Result Str {}
exe_path! : () => Result (List U8) {}
set_cwd! : List U8 => Result {} {}
