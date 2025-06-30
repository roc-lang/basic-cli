//! This crate provides common functionality for Roc to interface with `std::io`
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

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt; // used for is_executable, is_readable, is_writable

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

pub fn file_write_utf8(roc_path: &RocList<u8>, roc_str: &RocStr) -> RocResult<(), IOErr> {
    write_slice(roc_path, roc_str.as_str().as_bytes())
}

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
pub fn path_from_roc_path(bytes: &RocList<u8>) -> Cow<'_, Path> {
    use std::os::windows::ffi::OsStringExt;

    let bytes = bytes.as_slice();
    assert_eq!(bytes.len() % 2, 0);
    let characters: &[u16] =
        unsafe { std::slice::from_raw_parts(bytes.as_ptr().cast(), bytes.len() / 2) };

    let os_string = std::ffi::OsString::from_wide(characters);

    Cow::Owned(std::path::PathBuf::from(os_string))
}

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

pub fn file_delete(roc_path: &RocList<u8>) -> RocResult<(), IOErr> {
    match std::fs::remove_file(path_from_roc_path(roc_path)) {
        Ok(()) => RocResult::ok(()),
        Err(err) => RocResult::err(err.into()),
    }
}

/// Note: If the path is a directory or symlink, you probably don't want to call this function.
pub fn file_size_in_bytes(roc_path: &RocList<u8>) -> RocResult<u64, IOErr> {
    let rust_path = path_from_roc_path(roc_path);
    let metadata_res = std::fs::metadata(rust_path);

    match metadata_res {
        Ok(metadata) => {
            RocResult::ok(metadata.len())
        }
        Err(err) => {
            RocResult::err(err.into())
        }
    }
}

pub fn file_is_executable(roc_path: &RocList<u8>) -> RocResult<bool, IOErr> {
    let rust_path = path_from_roc_path(roc_path);

    #[cfg(unix)]
    {
        let metadata_res = std::fs::metadata(rust_path);

        match metadata_res {
            Ok(metadata) => {
                let permissions = metadata.permissions();
                RocResult::ok(permissions.mode() & 0o111 != 0)
            }
            Err(err) => {
                RocResult::err(err.into())
            }
        }
    }

    #[cfg(windows)]
    {
        RocResult::err(IOErr{
            msg: "Not yet implemented on windows.".into(),
            tag: IOErrTag::Unsupported,
        })
    }
}

pub fn file_is_readable(roc_path: &RocList<u8>) -> RocResult<bool, IOErr> {
    let rust_path = path_from_roc_path(roc_path);

    #[cfg(unix)]
    {
        let metadata_res = std::fs::metadata(rust_path);

        match metadata_res {
            Ok(metadata) => {
                let permissions = metadata.permissions();
                RocResult::ok(permissions.mode() & 0o400 != 0)
            }
            Err(err) => {
                RocResult::err(err.into())
            }
        }
    }

    #[cfg(windows)]
    {
        RocResult::err(IOErr{
            msg: "Not yet implemented on windows.".into(),
            tag: IOErrTag::Unsupported,
        })
    }
}

pub fn file_is_writable(roc_path: &RocList<u8>) -> RocResult<bool, IOErr> {
    let rust_path = path_from_roc_path(roc_path);

    #[cfg(unix)]
    {
        let metadata_res = std::fs::metadata(rust_path);

        match metadata_res {
            Ok(metadata) => {
                let permissions = metadata.permissions();
                RocResult::ok(permissions.mode() & 0o200 != 0)
            }
            Err(err) => {
                RocResult::err(err.into())
            }
        }
    }

    #[cfg(windows)]
    {
        RocResult::err(IOErr{
            msg: "Not yet implemented on windows.".into(),
            tag: IOErrTag::Unsupported,
        })
    }
}

pub fn file_time_accessed(roc_path: &RocList<u8>) -> RocResult<roc_std::U128, IOErr> {
    let rust_path = path_from_roc_path(roc_path);
    let metadata_res = std::fs::metadata(rust_path);

    match metadata_res {
        Ok(metadata) => {
            let accessed = metadata.accessed();
            match accessed {
                Ok(time) => {
                    RocResult::ok(
                        roc_std::U128::from(
                            time.duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()
                        )
                    )
                }
                Err(err) => {
                    RocResult::err(err.into())
                }
            }
        }
        Err(err) => {
            RocResult::err(err.into())
        }
    }
}

pub fn file_time_modified(roc_path: &RocList<u8>) -> RocResult<roc_std::U128, IOErr> {
    let rust_path = path_from_roc_path(roc_path);
    let metadata_res = std::fs::metadata(rust_path);

    match metadata_res {
        Ok(metadata) => {
            let modified = metadata.modified();
            match modified {
                Ok(time) => {
                    RocResult::ok(
                        roc_std::U128::from(
                            time.duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()
                        )
                    )
                }
                Err(err) => {
                    RocResult::err(err.into())
                }
            }
        }
        Err(err) => {
            RocResult::err(err.into())
        }
    }
}

pub fn file_time_created(roc_path: &RocList<u8>) -> RocResult<roc_std::U128, IOErr> {
    let rust_path = path_from_roc_path(roc_path);
    let metadata_res = std::fs::metadata(rust_path);

    match metadata_res {
        Ok(metadata) => {
            let created = metadata.created();
            match created {
                Ok(time) => {
                    RocResult::ok(
                        roc_std::U128::from(
                            time.duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()
                        )
                    )
                }
                Err(err) => {
                    RocResult::err(err.into())
                }
            }
        }
        Err(err) => {
            RocResult::err(err.into())
        }
    }
}

pub fn file_exists(roc_path: &RocList<u8>) -> RocResult<bool, IOErr> {
    let path = path_from_roc_path(roc_path);
    match path.try_exists() {
        Ok(exists) => RocResult::ok(exists),
        Err(err) => RocResult::err(err.into()),
    }
}

pub fn file_rename(from_path: &RocList<u8>, to_path: &RocList<u8>) -> RocResult<(), IOErr> {
    let rust_from_path = path_from_roc_path(from_path);
    let rust_to_path = path_from_roc_path(to_path);

    match std::fs::rename(rust_from_path, rust_to_path) {
        Ok(()) => RocResult::ok(()),
        Err(err) => RocResult::err(err.into()),
    }
}

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

pub fn dir_create(roc_path: &RocList<u8>) -> RocResult<(), IOErr> {
    match std::fs::create_dir(path_from_roc_path(roc_path)) {
        Ok(_) => RocResult::ok(()),
        Err(err) => RocResult::err(err.into()),
    }
}

pub fn dir_create_all(roc_path: &RocList<u8>) -> RocResult<(), IOErr> {
    match std::fs::create_dir_all(path_from_roc_path(roc_path)) {
        Ok(_) => RocResult::ok(()),
        Err(err) => RocResult::err(err.into()),
    }
}

pub fn dir_delete_empty(roc_path: &RocList<u8>) -> RocResult<(), IOErr> {
    match std::fs::remove_dir(path_from_roc_path(roc_path)) {
        Ok(_) => RocResult::ok(()),
        Err(err) => RocResult::err(err.into()),
    }
}

pub fn dir_delete_all(roc_path: &RocList<u8>) -> RocResult<(), IOErr> {
    match std::fs::remove_dir_all(path_from_roc_path(roc_path)) {
        Ok(_) => RocResult::ok(()),
        Err(err) => RocResult::err(err.into()),
    }
}

pub fn hard_link(path_from: &RocList<u8>, path_to: &RocList<u8>) -> RocResult<(), IOErr> {
    match std::fs::hard_link(path_from_roc_path(path_from), path_from_roc_path(path_to)) {
        Ok(_) => RocResult::ok(()),
        Err(err) => RocResult::err(err.into()),
    }
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
