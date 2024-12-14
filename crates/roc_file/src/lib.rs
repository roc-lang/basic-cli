use roc_io_error::{IOErr, IOErrTag};
use roc_std::{RocBox, RocList, RocResult, RocStr};
use roc_std_heap::ThreadSafeRefcountedResourceHeap;
use std::borrow::Cow;
use std::ffi::OsStr;
use std::fs::File;
use std::io::{BufRead, BufReader, ErrorKind, Read, Write};
use std::path::Path;
use std::sync::OnceLock;
use std::{env, io};

pub fn heap() -> &'static ThreadSafeRefcountedResourceHeap<BufReader<File>> {
    static FILE_HEAP: OnceLock<ThreadSafeRefcountedResourceHeap<BufReader<File>>> = OnceLock::new();
    FILE_HEAP.get_or_init(|| {
        let default_max_files = 65536;
        let max_files = env::var("ROC_BASIC_CLI_MAX_FILES")
            .map(|v| v.parse().unwrap_or(default_max_files))
            .unwrap_or(default_max_files);
        ThreadSafeRefcountedResourceHeap::new(max_files)
            .expect("Failed to allocate mmap for file handle references.")
    })
}

/// fileWriteUtf8! : List U8, Str => Result {} IOErr
pub fn file_write_utf8(roc_path: &RocList<u8>, roc_str: &RocStr) -> RocResult<(), IOErr> {
    write_slice(roc_path, roc_str.as_str().as_bytes())
}

/// fileWriteBytes! : List U8, List U8 => Result {} IOErr
pub fn file_write_bytes(roc_path: &RocList<u8>, roc_bytes: &RocList<u8>) -> RocResult<(), IOErr> {
    write_slice(roc_path, roc_bytes.as_slice())
}

fn write_slice(roc_path: &RocList<u8>, bytes: &[u8]) -> RocResult<(), IOErr> {
    match File::create(path_from_roc_path(roc_path)) {
        Ok(mut file) => match file.write_all(bytes) {
            Ok(()) => RocResult::ok(()),
            Err(err) => RocResult::err(err.into()),
        },
        Err(err) => RocResult::err(err.into()),
    }
}

#[repr(C)]
pub struct InternalPathType {
    is_dir: bool,
    is_file: bool,
    is_sym_link: bool,
}

/// pathType! : List U8 => Result InternalPathType IOErr
pub fn path_type(roc_path: &RocList<u8>) -> RocResult<InternalPathType, IOErr> {
    let path = path_from_roc_path(roc_path);
    match path.symlink_metadata() {
        Ok(m) => RocResult::ok(InternalPathType {
            is_dir: m.is_dir(),
            is_file: m.is_file(),
            is_sym_link: m.is_symlink(),
        }),
        Err(err) => RocResult::err(err.into()),
    }
}

#[cfg(target_family = "unix")]
pub fn path_from_roc_path(bytes: &RocList<u8>) -> Cow<'_, Path> {
    use std::os::unix::ffi::OsStrExt;
    let os_str = OsStr::from_bytes(bytes.as_slice());
    Cow::Borrowed(Path::new(os_str))
}

#[cfg(target_family = "windows")]
fn path_from_roc_path(bytes: &RocList<u8>) -> Cow<'_, Path> {
    use std::os::windows::ffi::OsStringExt;

    let bytes = bytes.as_slice();
    assert_eq!(bytes.len() % 2, 0);
    let characters: &[u16] =
        unsafe { std::slice::from_raw_parts(bytes.as_ptr().cast(), bytes.len() / 2) };

    let os_string = std::ffi::OsString::from_wide(characters);

    Cow::Owned(std::path::PathBuf::from(os_string))
}

/// fileReadBytes! : List U8 => Result (List U8) IOErr
pub fn file_read_bytes(roc_path: &RocList<u8>) -> RocResult<RocList<u8>, IOErr> {
    // TODO: write our own duplicate of `read_to_end` that directly fills a `RocList<u8>`.
    // This adds an extra O(n) copy.
    let mut bytes = Vec::new();

    match File::open(path_from_roc_path(roc_path)) {
        Ok(mut file) => match file.read_to_end(&mut bytes) {
            Ok(_bytes_read) => RocResult::ok(RocList::from(bytes.as_slice())),
            Err(err) => RocResult::err(err.into()),
        },
        Err(err) => RocResult::err(err.into()),
    }
}

/// fileReader! : List U8, U64 => Result FileReader IOErr
pub fn file_reader(roc_path: &RocList<u8>, size: u64) -> RocResult<RocBox<()>, IOErr> {
    match File::open(path_from_roc_path(roc_path)) {
        Ok(file) => {
            let buf_reader = if size > 0 {
                BufReader::with_capacity(size as usize, file)
            } else {
                BufReader::new(file)
            };

            let heap = heap();
            let alloc_result = heap.alloc_for(buf_reader);
            match alloc_result {
                Ok(out) => RocResult::ok(out),
                Err(err) => RocResult::err(err.into()),
            }
        }
        Err(err) => RocResult::err(err.into()),
    }
}

/// fileReadLine! : FileReader => Result (List U8) IOErr
pub fn file_read_line(data: RocBox<()>) -> RocResult<RocList<u8>, IOErr> {
    let buf_reader: &mut BufReader<File> = ThreadSafeRefcountedResourceHeap::box_to_resource(data);

    let mut buffer = RocList::empty();
    match read_until(buf_reader, b'\n', &mut buffer) {
        Ok(..) => {
            // Note: this returns an empty list when no bytes were read, e.g. End Of File
            RocResult::ok(buffer)
        }
        Err(err) => RocResult::err(err.into()),
    }
}

pub fn read_until<R: BufRead + ?Sized>(
    r: &mut R,
    delim: u8,
    buf: &mut RocList<u8>,
) -> io::Result<usize> {
    let mut read = 0;
    loop {
        let (done, used) = {
            let available = match r.fill_buf() {
                Ok(n) => n,
                Err(ref e) if matches!(e.kind(), ErrorKind::Interrupted) => continue,
                Err(e) => return Err(e),
            };
            match memchr::memchr(delim, available) {
                Some(i) => {
                    buf.extend_from_slice(&available[..=i]);
                    (true, i + 1)
                }
                None => {
                    buf.extend_from_slice(available);
                    (false, available.len())
                }
            }
        };
        r.consume(used);
        read += used;
        if done || used == 0 {
            return Ok(read);
        }
    }
}

/// fileDelete! : List U8 => Result {} IOErr
pub fn file_delete(roc_path: &RocList<u8>) -> RocResult<(), IOErr> {
    match std::fs::remove_file(path_from_roc_path(roc_path)) {
        Ok(()) => RocResult::ok(()),
        Err(err) => RocResult::err(err.into()),
    }
}

/// cwd! : {} => Result (List U8) {}
pub fn cwd() -> RocResult<RocList<u8>, ()> {
    // TODO instead, call getcwd on UNIX and GetCurrentDirectory on Windows
    match std::env::current_dir() {
        Ok(path_buf) => RocResult::ok(os_str_to_roc_path(path_buf.into_os_string().as_os_str())),
        Err(_) => {
            // Default to empty path
            RocResult::ok(RocList::empty())
        }
    }
}

/// dirList! : List U8 => Result (List (List U8)) IOErr
pub fn dir_list(roc_path: &RocList<u8>) -> RocResult<RocList<RocList<u8>>, IOErr> {
    let path = path_from_roc_path(roc_path);

    if path.is_dir() {
        let dir = match std::fs::read_dir(path) {
            Ok(dir) => dir,
            Err(err) => return RocResult::err(err.into()),
        };

        let mut entries = Vec::new();

        for entry in dir.flatten() {
            let path = entry.path();
            let str = path.as_os_str();
            entries.push(os_str_to_roc_path(str));
        }

        RocResult::ok(RocList::from_iter(entries))
    } else {
        RocResult::err(IOErr {
            msg: "NotADirectory".into(),
            tag: IOErrTag::Other,
        })
    }
}

/// dirCreate! : List U8 => Result {} IOErr
pub fn dir_create(roc_path: &RocList<u8>) -> RocResult<(), IOErr> {
    match std::fs::create_dir(path_from_roc_path(roc_path)) {
        Ok(_) => RocResult::ok(()),
        Err(err) => RocResult::err(err.into()),
    }
}

/// dirCreateAll! : List U8 => Result {} IOErr
pub fn dir_create_all(roc_path: &RocList<u8>) -> RocResult<(), IOErr> {
    match std::fs::create_dir_all(path_from_roc_path(roc_path)) {
        Ok(_) => RocResult::ok(()),
        Err(err) => RocResult::err(err.into()),
    }
}

/// dirDeleteEmpty! : List U8 => Result {} IOErr
pub fn dir_delete_empty(roc_path: &RocList<u8>) -> RocResult<(), IOErr> {
    match std::fs::remove_dir(path_from_roc_path(roc_path)) {
        Ok(_) => RocResult::ok(()),
        Err(err) => RocResult::err(err.into()),
    }
}

/// dirDeleteAll! : List U8 => Result {} IOErr
pub fn dir_delete_all(roc_path: &RocList<u8>) -> RocResult<(), IOErr> {
    match std::fs::remove_dir_all(path_from_roc_path(roc_path)) {
        Ok(_) => RocResult::ok(()),
        Err(err) => RocResult::err(err.into()),
    }
}

/// hardLink! : List U8 => Result {} IOErr
pub fn hard_link(path_from: &RocList<u8>, path_to: &RocList<u8>) -> RocResult<(), IOErr> {
    match std::fs::hard_link(path_from_roc_path(path_from), path_from_roc_path(path_to)) {
        Ok(_) => RocResult::ok(()),
        Err(err) => RocResult::err(err.into()),
    }
}

/// tempDir! : {} => List U8
pub fn temp_dir() -> RocList<u8> {
    let path_os_string_bytes = std::env::temp_dir().into_os_string().into_encoded_bytes();

    RocList::from(path_os_string_bytes.as_slice())
}

#[cfg(target_family = "unix")]
pub fn os_str_to_roc_path(os_str: &OsStr) -> RocList<u8> {
    use std::os::unix::ffi::OsStrExt;

    RocList::from(os_str.as_bytes())
}

#[cfg(target_family = "windows")]
pub fn os_str_to_roc_path(os_str: &OsStr) -> RocList<u8> {
    use std::os::windows::ffi::OsStrExt;

    let bytes: Vec<_> = os_str.encode_wide().flat_map(|c| c.to_be_bytes()).collect();

    RocList::from(bytes.as_slice())
}
