//! The buffered writer behind `File.Writer`.
//!
//! Bytes reach the operating system when the buffer fills and on `flush`. A
//! write accepts all of its bytes or fails. There is no close: the file is
//! closed when the last reference to the handle is released, which may happen
//! inside `roc_dealloc` when compiled Roc frees the handle itself. Dropping a
//! `BufWriter` flushes what is still buffered and discards any error, and it
//! neither allocates through Roc nor touches another handle, so it is safe to
//! run there.
use crate::roc_platform_abi::*;
use crate::{
    file_io_err_from_io, normalize_file_kind_err, path_from_native, resources, roc_host,
    try_file_delete_err, try_file_delete_ok,
};
use core::mem::ManuallyDrop;
use std::fs::{File, OpenOptions};
use std::io::{self, BufWriter, Write};
use std::path::Path;

/// The resource behind a `Resource.FileWriter` handle.
pub struct FileWriter(BufWriter<File>);

/// What `File.WriteMode` asks of the file that is opened.
type WriteMode = AppendOrRequireNewOrTruncate;

fn open_options(mode: WriteMode) -> OpenOptions {
    let mut options = OpenOptions::new();
    match mode {
        // Create the file or empty it.
        WriteMode::Truncate => options.write(true).create(true).truncate(true),
        // Create the file if it is missing; every write goes to the end.
        WriteMode::Append => options.append(true).create(true),
        // Fail with `AlreadyExists` if anything is at the path, including a
        // directory or a dangling symbolic link.
        WriteMode::RequireNew => options.write(true).create_new(true),
    };
    options
}

impl FileWriter {
    pub fn open(path: &Path, mode: WriteMode) -> io::Result<Self> {
        Self::open_with_capacity(path, mode, None)
    }

    fn open_with_capacity(
        path: &Path,
        mode: WriteMode,
        capacity: Option<usize>,
    ) -> io::Result<Self> {
        match open_options(mode).open(path) {
            Ok(file) => Ok(Self(match capacity {
                Some(capacity) => BufWriter::with_capacity(capacity, file),
                None => BufWriter::new(file),
            })),
            // Some systems refuse to create a file over a directory with
            // another error; `RequireNew` reports whatever is there the same way.
            Err(error)
                if mode == WriteMode::RequireNew
                    && error.kind() != io::ErrorKind::AlreadyExists
                    && path.symlink_metadata().is_ok() =>
            {
                Err(io::ErrorKind::AlreadyExists.into())
            }
            Err(error) => Err(normalize_file_kind_err(path, error)),
        }
    }

    /// Accept every byte, in the buffer or in the file, or fail.
    pub fn write(&mut self, bytes: &[u8]) -> io::Result<()> {
        self.0.write_all(bytes)
    }

    /// Hand every buffered byte to the operating system.
    pub fn flush(&mut self) -> io::Result<()> {
        self.0.flush()
    }
}

fn unit_result(result: io::Result<()>, roc_host: &RocHost) -> HostFileDeleteResult {
    match result {
        Ok(()) => try_file_delete_ok(),
        Err(error) => try_file_delete_err(file_io_err_from_io(&error, roc_host)),
    }
}

fn open_err(error: &io::Error, roc_host: &RocHost) -> HostFileOpenWriterResult {
    HostFileOpenWriterResult {
        payload: HostFileOpenWriterResultPayload {
            err: ManuallyDrop::new(file_io_err_from_io(error, roc_host)),
        },
        tag: HostFileOpenWriterResultTag::Err,
    }
}

#[no_mangle]
pub extern "C" fn hosted_file_open_writer(
    path: UnixBytesOrUtf8OrWindowsU16s,
    mode: AppendOrRequireNewOrTruncate,
) -> HostFileOpenWriterResult {
    let roc_host = roc_host();
    let path = match path_from_native(path, roc_host) {
        Ok(path) => path,
        Err(error) => return open_err(&error, roc_host),
    };
    let writer = match FileWriter::open(&path, mode) {
        Ok(writer) => writer,
        Err(error) => return open_err(&error, roc_host),
    };
    match resources::box_resource(writer, roc_host) {
        Ok(handle) => HostFileOpenWriterResult {
            payload: HostFileOpenWriterResultPayload {
                ok: ManuallyDrop::new(handle),
            },
            tag: HostFileOpenWriterResultTag::Ok,
        },
        Err(error) => open_err(&error, roc_host),
    }
}

/// # Safety
///
/// `handle` must be a live file writer handle from `hosted_file_open_writer`.
#[no_mangle]
pub unsafe extern "C" fn hosted_file_writer_write_bytes(
    handle: *mut u64,
    bytes: RocListWith<u8, false>,
) -> HostFileWriterWriteBytesResult {
    let roc_host = roc_host();
    let writer = unsafe { resources::resource_ref::<FileWriter>(handle) };
    let result = unit_result(writer.write(bytes.as_slice()), roc_host);
    unsafe { bytes.decref(roc_host) };
    resources::release(handle, roc_host);
    result
}

/// # Safety
///
/// `handle` must be a live file writer handle from `hosted_file_open_writer`.
#[no_mangle]
pub unsafe extern "C" fn hosted_file_writer_write_utf8(
    handle: *mut u64,
    text: RocStr,
) -> HostFileWriterWriteUtf8Result {
    let roc_host = roc_host();
    let writer = unsafe { resources::resource_ref::<FileWriter>(handle) };
    let result = unit_result(writer.write(text.as_str().as_bytes()), roc_host);
    unsafe { text.decref(roc_host) };
    resources::release(handle, roc_host);
    result
}

/// # Safety
///
/// `handle` must be a live file writer handle from `hosted_file_open_writer`.
#[no_mangle]
pub unsafe extern "C" fn hosted_file_writer_flush(handle: *mut u64) -> HostFileWriterFlushResult {
    let roc_host = roc_host();
    let writer = unsafe { resources::resource_ref::<FileWriter>(handle) };
    let result = unit_result(writer.flush(), roc_host);
    resources::release(handle, roc_host);
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn workspace(name: &str) -> tempfile::TempDir {
        tempfile::Builder::new()
            .prefix(&format!("basic-cli-file-writer-{name}-"))
            .tempdir()
            .unwrap()
    }

    fn write_all(path: &Path, mode: WriteMode, bytes: &[u8]) {
        let mut writer = FileWriter::open(path, mode).unwrap();
        writer.write(bytes).unwrap();
        writer.flush().unwrap();
    }

    #[test]
    fn truncate_creates_the_file_or_empties_it() {
        let dir = workspace("truncate");
        let path = dir.path().join("report.csv");
        write_all(&path, WriteMode::Truncate, b"first, and longer");
        assert_eq!(fs::read(&path).unwrap(), b"first, and longer");
        write_all(&path, WriteMode::Truncate, b"second");
        assert_eq!(fs::read(&path).unwrap(), b"second");
        // Opening is enough to empty the file.
        drop(FileWriter::open(&path, WriteMode::Truncate).unwrap());
        assert_eq!(fs::read(&path).unwrap(), b"");
    }

    #[test]
    fn append_creates_the_file_and_keeps_what_it_holds() {
        let dir = workspace("append");
        let path = dir.path().join("events.log");
        write_all(&path, WriteMode::Append, b"one\n");
        write_all(&path, WriteMode::Append, b"two\n");
        assert_eq!(fs::read(&path).unwrap(), b"one\ntwo\n");

        // Two writers on one file both write at its end, wherever that is now.
        let mut first = FileWriter::open(&path, WriteMode::Append).unwrap();
        let mut second = FileWriter::open(&path, WriteMode::Append).unwrap();
        first.write(b"three\n").unwrap();
        first.flush().unwrap();
        second.write(b"four\n").unwrap();
        second.flush().unwrap();
        assert_eq!(fs::read(&path).unwrap(), b"one\ntwo\nthree\nfour\n");
    }

    #[test]
    fn require_new_fails_if_anything_is_at_the_path() {
        let dir = workspace("require-new");
        let path = dir.path().join("fresh.txt");
        write_all(&path, WriteMode::RequireNew, b"mine");
        assert_eq!(fs::read(&path).unwrap(), b"mine");

        let exists = |path: &Path| {
            FileWriter::open(path, WriteMode::RequireNew)
                .err()
                .expect("opened a path that exists")
                .kind()
        };
        assert_eq!(exists(&path), io::ErrorKind::AlreadyExists);
        // The existing file is untouched.
        assert_eq!(fs::read(&path).unwrap(), b"mine");
        assert_eq!(exists(dir.path()), io::ErrorKind::AlreadyExists);

        #[cfg(unix)]
        {
            let dangling = dir.path().join("dangling");
            std::os::unix::fs::symlink(dir.path().join("missing"), &dangling).unwrap();
            assert_eq!(exists(&dangling), io::ErrorKind::AlreadyExists);
            assert!(!dir.path().join("missing").exists());
        }
    }

    #[test]
    fn opening_fails_without_a_parent_directory_or_on_a_directory() {
        let dir = workspace("open-errors");
        for mode in [
            WriteMode::Truncate,
            WriteMode::Append,
            WriteMode::RequireNew,
        ] {
            let error = FileWriter::open(&dir.path().join("missing/file.txt"), mode)
                .err()
                .unwrap();
            assert_eq!(error.kind(), io::ErrorKind::NotFound, "{mode:?}");
        }
        for mode in [WriteMode::Truncate, WriteMode::Append] {
            let error = FileWriter::open(dir.path(), mode).err().unwrap();
            assert_eq!(error.kind(), io::ErrorKind::IsADirectory, "{mode:?}");
        }
    }

    #[test]
    fn bytes_stay_in_the_buffer_until_it_fills_or_is_flushed() {
        let dir = workspace("buffering");
        let path = dir.path().join("buffered.bin");
        let mut writer =
            FileWriter::open_with_capacity(&path, WriteMode::Truncate, Some(8)).unwrap();

        writer.write(b"abc").unwrap();
        writer.write(b"de").unwrap();
        assert_eq!(fs::read(&path).unwrap(), b"", "held in the buffer");

        // A write that does not fit beside the buffered bytes pushes them out.
        writer.write(b"fghij").unwrap();
        assert_eq!(fs::read(&path).unwrap(), b"abcde");
        writer.flush().unwrap();
        assert_eq!(fs::read(&path).unwrap(), b"abcdefghij");

        // A write larger than the buffer is not split or shortened.
        let large: Vec<u8> = (0..200_000).map(|i| i as u8).collect();
        writer.write(b"k").unwrap();
        writer.write(&large).unwrap();
        writer.write(b"").unwrap();
        writer.flush().unwrap();
        writer.flush().unwrap();
        let mut expected = b"abcdefghijk".to_vec();
        expected.extend(&large);
        assert_eq!(fs::read(&path).unwrap(), expected);
    }

    #[test]
    fn the_default_buffer_holds_small_writes() {
        let dir = workspace("default-buffer");
        let path = dir.path().join("lines.txt");
        let mut writer = FileWriter::open(&path, WriteMode::Truncate).unwrap();
        for _ in 0..10 {
            writer.write(b"line\n").unwrap();
        }
        assert_eq!(fs::read(&path).unwrap(), b"");
        writer.flush().unwrap();
        assert_eq!(fs::read(&path).unwrap(), b"line\n".repeat(10));
    }

    #[test]
    fn dropping_a_writer_flushes_its_buffer() {
        let dir = workspace("drop");
        let path = dir.path().join("dropped.txt");
        let mut writer = FileWriter::open(&path, WriteMode::Truncate).unwrap();
        writer.write(b"never flushed").unwrap();
        assert_eq!(fs::read(&path).unwrap(), b"");
        drop(writer);
        assert_eq!(fs::read(&path).unwrap(), b"never flushed");
    }

    fn allocation_base(handle: *mut u64) -> *mut std::ffi::c_void {
        unsafe { handle.cast::<u8>().sub(resources::HEADER_BYTES).cast() }
    }

    fn live_writers() -> usize {
        resources::live_handles()
            .find(|(kind, _)| *kind == resources::Kind::FileWriter)
            .unwrap()
            .1
    }

    // Both ways a handle dies run the destructor inside the allocator's free:
    // the host dropping the last reference, and compiled Roc decrementing to
    // zero and calling `roc_dealloc` itself. Serialised in one test because
    // both assert on the kind's live-handle count.
    #[test]
    fn releasing_the_last_reference_flushes_and_closes_the_file() {
        let dir = workspace("release");
        let mut host = resources::make_host();
        let before = live_writers();

        let released = dir.path().join("released.txt");
        let handle = resources::box_resource(
            FileWriter::open(&released, WriteMode::Truncate).unwrap(),
            &host,
        )
        .unwrap();
        assert_eq!(live_writers(), before + 1);
        // A second reference, as a hosted call's argument would hold.
        unsafe { incref_box(handle.cast(), 1) };
        unsafe { resources::resource_ref::<FileWriter>(handle) }
            .write(b"buffered, then released")
            .unwrap();
        resources::release(handle, &host);
        assert_eq!(fs::read(&released).unwrap(), b"", "still referenced");
        resources::release(handle, &host);
        assert_eq!(fs::read(&released).unwrap(), b"buffered, then released");
        assert_eq!(live_writers(), before);

        let freed = dir.path().join("freed.txt");
        let handle = resources::box_resource(
            FileWriter::open(&freed, WriteMode::Truncate).unwrap(),
            &host,
        )
        .unwrap();
        unsafe { resources::resource_ref::<FileWriter>(handle) }
            .write(b"buffered, then freed by Roc")
            .unwrap();
        assert_eq!(fs::read(&freed).unwrap(), b"");
        resources::dealloc(&mut host, allocation_base(handle), align_of::<u64>());
        assert_eq!(fs::read(&freed).unwrap(), b"buffered, then freed by Roc");
        assert_eq!(live_writers(), before);

        // The file really is closed: on Windows an open handle would stop this.
        fs::remove_file(&freed).unwrap();
        fs::remove_file(&released).unwrap();

        // A flush that fails while the handle is destroyed is discarded: the
        // free completes and the slot is recycled. /dev/full accepts the open
        // and fails every write with ENOSPC.
        #[cfg(target_os = "linux")]
        {
            let mut writer = FileWriter::open(Path::new("/dev/full"), WriteMode::Append).unwrap();
            writer.write(b"lost").unwrap();
            assert!(writer.flush().is_err());
            let handle = resources::box_resource(writer, &host).unwrap();
            resources::release(handle, &host);
            assert_eq!(live_writers(), before);
        }
    }
}
