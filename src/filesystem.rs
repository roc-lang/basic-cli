//! Native filesystem operations. Paths never pass through a Unicode conversion.
use std::{
    collections::HashSet,
    fs, io,
    path::{Component, Path, PathBuf},
};

#[derive(Clone, Copy, Debug)]
pub(crate) struct CopyOptions {
    pub preserve_links: bool,
    pub merge: bool,
}
#[derive(Debug)]
pub(crate) struct CopyError {
    pub operation: &'static str,
    pub source: PathBuf,
    pub destination: PathBuf,
    pub error: io::Error,
}
fn failure(
    operation: &'static str,
    source: &Path,
    destination: &Path,
    error: io::Error,
) -> CopyError {
    CopyError {
        operation,
        source: source.into(),
        destination: destination.into(),
        error,
    }
}
fn invalid(message: &'static str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput, message)
}

pub(crate) fn create_temp_dir(parent: &Path, prefix: &str) -> io::Result<PathBuf> {
    if prefix.contains(['/', '\\', ':', '\0']) || prefix == "." || prefix == ".." {
        return Err(invalid(
            "temporary directory prefix must be a filename component",
        ));
    }
    let mut builder = tempfile::Builder::new();
    builder.prefix(prefix);
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        builder.permissions(fs::Permissions::from_mode(0o700));
    }
    Ok(builder.tempdir_in(parent)?.keep())
}

// Resolve existing ancestors, including links, without requiring the leaf to exist.
fn prospective_canonical(path: &Path) -> io::Result<PathBuf> {
    match fs::canonicalize(path) {
        Ok(path) => Ok(path),
        Err(e) if e.kind() == io::ErrorKind::NotFound => {
            let absolute = std::path::absolute(path)?;
            let mut resolved = PathBuf::new();
            for component in absolute.components() {
                match component {
                    Component::ParentDir => {
                        resolved.pop();
                    }
                    Component::CurDir => {}
                    other => {
                        resolved.push(other.as_os_str());
                        match fs::canonicalize(&resolved) {
                            Ok(real) => resolved = real,
                            Err(e) if e.kind() == io::ErrorKind::NotFound => {}
                            Err(e) => return Err(e),
                        }
                    }
                }
            }
            Ok(resolved)
        }
        Err(e) => Err(e),
    }
}

pub(crate) fn copy_file(source: &Path, destination: &Path) -> Result<(), CopyError> {
    let run = || -> io::Result<()> {
        if !fs::metadata(source)?.is_file() {
            return Err(invalid("source is not a regular file"));
        }
        match fs::metadata(destination) {
            Ok(metadata) => {
                if !metadata.is_file() {
                    return Err(invalid("destination is not a regular file"));
                }
                if same_file::is_same_file(source, destination)? {
                    return Err(invalid("source and destination identify the same file"));
                }
            }
            Err(e) if e.kind() == io::ErrorKind::NotFound => {}
            Err(e) => return Err(e),
        }
        fs::copy(source, destination)?;
        Ok(())
    };
    run().map_err(|e| failure("copy_file", source, destination, e))
}

pub(crate) fn copy_dir(
    source: &Path,
    destination: &Path,
    options: CopyOptions,
) -> Result<(), CopyError> {
    let src =
        fs::canonicalize(source).map_err(|e| failure("resolve_source", source, destination, e))?;
    let dst = prospective_canonical(destination)
        .map_err(|e| failure("resolve_destination", source, destination, e))?;
    if dst.starts_with(&src) || src.starts_with(&dst) {
        return Err(failure(
            "copy_dir",
            source,
            destination,
            invalid("source and destination trees overlap"),
        ));
    }
    copy_tree(source, destination, options, &mut HashSet::new())
}

fn copy_tree(
    source: &Path,
    destination: &Path,
    options: CopyOptions,
    ancestors: &mut HashSet<PathBuf>,
) -> Result<(), CopyError> {
    let resolved =
        fs::canonicalize(source).map_err(|e| failure("resolve_source", source, destination, e))?;
    let resolved_destination = prospective_canonical(destination)
        .map_err(|e| failure("resolve_destination", source, destination, e))?;
    if resolved_destination.starts_with(&resolved) {
        return Err(failure(
            "copy_dir",
            source,
            destination,
            invalid("destination is inside source"),
        ));
    }
    if !ancestors.insert(resolved.clone()) {
        return Err(failure(
            "copy_dir",
            source,
            destination,
            invalid("symbolic link cycle"),
        ));
    }
    let result = (|| {
        let metadata =
            fs::metadata(source).map_err(|e| failure("metadata", source, destination, e))?;
        if !metadata.is_dir() {
            return Err(failure(
                "copy_dir",
                source,
                destination,
                io::Error::from(io::ErrorKind::NotADirectory),
            ));
        }
        if let Some(parent) = destination
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
        {
            fs::create_dir_all(parent)
                .map_err(|e| failure("create_parent_dirs", source, destination, e))?;
        }
        match fs::create_dir(destination) {
            Ok(()) => {}
            Err(e) if options.merge && e.kind() == io::ErrorKind::AlreadyExists => {
                let dst = fs::symlink_metadata(destination)
                    .map_err(|e| failure("metadata", source, destination, e))?;
                if !dst.is_dir() {
                    return Err(failure(
                        "create_dir",
                        source,
                        destination,
                        io::Error::from(io::ErrorKind::NotADirectory),
                    ));
                }
            }
            Err(e) => return Err(failure("create_dir", source, destination, e)),
        }
        let entries =
            fs::read_dir(source).map_err(|e| failure("read_dir", source, destination, e))?;
        for entry in entries {
            let entry = entry.map_err(|e| failure("read_dir_entry", source, destination, e))?;
            let src = entry.path();
            let dst = destination.join(entry.file_name());
            let metadata =
                fs::symlink_metadata(&src).map_err(|e| failure("metadata", &src, &dst, e))?;
            if metadata.is_symlink() && options.preserve_links {
                copy_link(&src, &dst).map_err(|e| failure("copy_symlink", &src, &dst, e))?;
            } else {
                let metadata =
                    fs::metadata(&src).map_err(|e| failure("metadata", &src, &dst, e))?;
                if metadata.is_dir() {
                    copy_tree(&src, &dst, options, ancestors)?;
                } else {
                    copy_file(&src, &dst)?;
                }
            }
        }
        fs::set_permissions(destination, metadata.permissions())
            .map_err(|e| failure("set_permissions", source, destination, e))
    })();
    ancestors.remove(&resolved);
    result
}

fn copy_link(source: &Path, destination: &Path) -> io::Result<()> {
    let target = fs::read_link(source)?;
    #[cfg(unix)]
    {
        std::os::unix::fs::symlink(target, destination)
    }
    #[cfg(windows)]
    {
        use std::os::windows::fs::{symlink_dir, symlink_file, FileTypeExt};
        if fs::symlink_metadata(source)?.file_type().is_symlink_dir() {
            symlink_dir(target, destination)
        } else {
            symlink_file(target, destination)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    const DEFAULT: CopyOptions = CopyOptions {
        preserve_links: false,
        merge: false,
    };
    #[test]
    fn copy_bytes_modes_and_merge() {
        let temp = tempfile::tempdir().unwrap();
        let src = temp.path().join("src");
        let dst = temp.path().join("dst");
        fs::create_dir(&src).unwrap();
        fs::write(src.join("file"), vec![255; 131073]).unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(src.join("file"), fs::Permissions::from_mode(0o751)).unwrap();
        }
        copy_dir(&src, &dst, DEFAULT).unwrap();
        assert_eq!(fs::read(dst.join("file")).unwrap(), vec![255; 131073]);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                fs::metadata(dst.join("file")).unwrap().permissions().mode() & 0o777,
                0o751
            );
        }
        assert!(copy_dir(&src, &dst, DEFAULT).is_err());
        copy_dir(
            &src,
            &dst,
            CopyOptions {
                merge: true,
                ..DEFAULT
            },
        )
        .unwrap();
        assert!(copy_dir(&src, &src.join("nested"), DEFAULT).is_err());
        fs::hard_link(src.join("file"), temp.path().join("alias")).unwrap();
        assert!(copy_file(&src.join("file"), &temp.path().join("alias")).is_err());
        assert_eq!(fs::metadata(src.join("file")).unwrap().len(), 131073);
    }
    #[test]
    fn merge_cannot_write_back_into_source() {
        let root = tempfile::tempdir().unwrap();
        let source = root.path().join("source");
        fs::create_dir_all(source.join("source")).unwrap();
        fs::write(source.join("source/file"), b"original").unwrap();
        assert!(copy_dir(
            &source,
            root.path(),
            CopyOptions {
                merge: true,
                ..DEFAULT
            }
        )
        .is_err());
        assert_eq!(fs::read(source.join("source/file")).unwrap(), b"original");
    }
    #[test]
    fn copy_tree_creates_missing_destination_parents() {
        let root = tempfile::tempdir().unwrap();
        let source = root.path().join("source");
        fs::create_dir(&source).unwrap();
        fs::write(source.join("file"), b"data").unwrap();
        let destination = root.path().join("missing/parents/copy");
        copy_dir(&source, &destination, DEFAULT).unwrap();
        assert_eq!(fs::read(destination.join("file")).unwrap(), b"data");
    }
    #[test]
    fn temporary_names_permissions_and_cleanup() {
        let parent = tempfile::tempdir().unwrap();
        let a = create_temp_dir(parent.path(), "roc-").unwrap();
        let b = create_temp_dir(parent.path(), "roc-").unwrap();
        assert_ne!(a, b);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                fs::metadata(&a).unwrap().permissions().mode() & 0o777,
                0o700
            );
        }
        for bad in ["../escape", "a/b", "a\\b", "C:escape", "..", "\0"] {
            assert!(create_temp_dir(parent.path(), bad).is_err());
        }
    }
    #[cfg(unix)]
    #[test]
    fn links_cycles_and_native_names() {
        #[cfg(not(target_vendor = "apple"))]
        use std::os::unix::ffi::OsStrExt;
        use std::os::unix::fs::symlink;
        let temp = tempfile::tempdir().unwrap();
        let src = temp.path().join("src");
        fs::create_dir(&src).unwrap();
        #[cfg(not(target_vendor = "apple"))]
        {
            let name = std::ffi::OsStr::from_bytes(b"raw\xff");
            fs::write(src.join(name), b"hello").unwrap();
        }
        symlink("missing", src.join("dangling")).unwrap();
        let dst = temp.path().join("preserved");
        copy_dir(
            &src,
            &dst,
            CopyOptions {
                preserve_links: true,
                ..DEFAULT
            },
        )
        .unwrap();
        #[cfg(not(target_vendor = "apple"))]
        assert_eq!(
            fs::read(dst.join(std::ffi::OsStr::from_bytes(b"raw\xff"))).unwrap(),
            b"hello"
        );
        assert_eq!(
            fs::read_link(dst.join("dangling")).unwrap(),
            Path::new("missing")
        );
        assert!(copy_dir(&src, &temp.path().join("follow"), DEFAULT).is_err());
        fs::remove_file(src.join("dangling")).unwrap();
        symlink(".", src.join("cycle")).unwrap();
        assert!(copy_dir(&src, &temp.path().join("cycle"), DEFAULT).is_err());
        symlink(&src, temp.path().join("alias")).unwrap();
        assert!(copy_dir(&src, &temp.path().join("alias/new"), DEFAULT).is_err());
    }
}

#[cfg(all(test, unix))]
mod unix_tests {
    use super::*;
    use std::{ffi::CString, os::unix::ffi::OsStrExt};
    #[test]
    fn special_files_are_rejected_without_blocking() {
        let root = tempfile::tempdir().unwrap();
        let fifo = root.path().join("fifo");
        let cpath = CString::new(fifo.as_os_str().as_bytes()).unwrap();
        assert_eq!(unsafe { libc::mkfifo(cpath.as_ptr(), 0o600) }, 0);
        assert!(copy_file(&fifo, &root.path().join("copy")).is_err());
        let file = root.path().join("file");
        fs::write(&file, b"safe").unwrap();
        assert!(copy_file(&file, &fifo).is_err());
    }
    #[test]
    fn directory_permissions_are_applied_after_children() {
        use std::os::unix::fs::PermissionsExt;
        let root = tempfile::tempdir().unwrap();
        let src = root.path().join("source");
        let dst = root.path().join("destination");
        fs::create_dir_all(src.join("nested")).unwrap();
        fs::write(src.join("nested/file"), b"ok").unwrap();
        fs::set_permissions(src.join("nested"), fs::Permissions::from_mode(0o500)).unwrap();
        copy_dir(
            &src,
            &dst,
            CopyOptions {
                preserve_links: false,
                merge: false,
            },
        )
        .unwrap();
        assert_eq!(fs::read(dst.join("nested/file")).unwrap(), b"ok");
        assert_eq!(
            fs::metadata(dst.join("nested"))
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o500
        );
        for path in [src.join("nested"), dst.join("nested")] {
            fs::set_permissions(path, fs::Permissions::from_mode(0o700)).unwrap();
        }
    }
    #[test]
    fn external_links_follow_and_preserve_with_merge_conflicts() {
        use std::os::unix::fs::symlink;
        let root = tempfile::tempdir().unwrap();
        let source = root.path().join("source");
        let external = root.path().join("external");
        fs::create_dir(&source).unwrap();
        fs::create_dir(&external).unwrap();
        fs::write(external.join("data"), b"external").unwrap();
        symlink(&external, source.join("link")).unwrap();
        let followed = root.path().join("followed");
        copy_dir(
            &source,
            &followed,
            CopyOptions {
                preserve_links: false,
                merge: false,
            },
        )
        .unwrap();
        assert!(!fs::symlink_metadata(followed.join("link"))
            .unwrap()
            .is_symlink());
        assert_eq!(fs::read(followed.join("link/data")).unwrap(), b"external");
        let preserved = root.path().join("preserved");
        fs::create_dir(&preserved).unwrap();
        copy_dir(
            &source,
            &preserved,
            CopyOptions {
                preserve_links: true,
                merge: true,
            },
        )
        .unwrap();
        assert_eq!(fs::read_link(preserved.join("link")).unwrap(), external);
        let err = copy_dir(
            &source,
            &preserved,
            CopyOptions {
                preserve_links: true,
                merge: true,
            },
        )
        .unwrap_err();
        assert_eq!(err.operation, "copy_symlink");
        assert_eq!(err.error.kind(), io::ErrorKind::AlreadyExists);
        assert_eq!(err.source, source.join("link"));
        assert_eq!(err.destination, preserved.join("link"));
        assert!(copy_dir(
            &source,
            &preserved,
            CopyOptions {
                preserve_links: false,
                merge: true
            }
        )
        .is_err());
    }
    #[test]
    fn concurrent_temporary_directories_are_unique() {
        let root = tempfile::tempdir().unwrap();
        let paths = std::thread::scope(|scope| {
            let threads: Vec<_> = (0..24)
                .map(|_| scope.spawn(|| create_temp_dir(root.path(), "same-").unwrap()))
                .collect();
            threads
                .into_iter()
                .map(|thread| thread.join().unwrap())
                .collect::<HashSet<_>>()
        });
        assert_eq!(paths.len(), 24);
    }
}

// Hosted adapters own each incoming Roc value and release it after conversion.
use crate::roc_platform_abi::*;
use crate::{dir_io_err_from_io, native_path_from_path, path_from_native, roc_host};
use core::mem::ManuallyDrop;

fn copy_result(result: Result<(), CopyError>) -> HostPathCopyResult {
    match result {
        Ok(()) => HostPathCopyResult {
            tag: HostPathCopyResultTag::Ok,
            payload: HostPathCopyResultPayload { ok: [] },
        },
        Err(error) => copy_failure_result(HostPathCopyErr {
            operation: RocStr::from_str(error.operation, roc_host()),
            source: native_path_from_path(&error.source, roc_host()),
            destination: native_path_from_path(&error.destination, roc_host()),
            error: dir_io_err_from_io(&error.error, roc_host()),
        }),
    }
}
fn copy_failure_result(error: HostPathCopyErr) -> HostPathCopyResult {
    HostPathCopyResult {
        tag: HostPathCopyResultTag::Err,
        payload: HostPathCopyResultPayload {
            err: ManuallyDrop::new(error),
        },
    }
}
fn decode_copy_paths(
    source: UnixBytesOrUtf8OrWindowsU16s,
    destination: UnixBytesOrUtf8OrWindowsU16s,
) -> Result<(PathBuf, PathBuf), HostPathCopyErr> {
    // Retain the originals for errors such as an unsupported native representation.
    unsafe {
        source.incref(1);
        destination.incref(1);
    }
    let source_path = path_from_native(source, roc_host());
    let destination_path = path_from_native(destination, roc_host());
    match (source_path, destination_path) {
        (Ok(src), Ok(dst)) => {
            unsafe {
                source.decref(roc_host());
                destination.decref(roc_host());
            }
            Ok((src, dst))
        }
        (Err(error), _) | (_, Err(error)) => Err(HostPathCopyErr {
            operation: RocStr::from_str("decode_path", roc_host()),
            source,
            destination,
            error: dir_io_err_from_io(&error, roc_host()),
        }),
    }
}

#[no_mangle]
pub extern "C" fn hosted_path_copy(
    source: UnixBytesOrUtf8OrWindowsU16s,
    destination: UnixBytesOrUtf8OrWindowsU16s,
) -> HostPathCopyResult {
    match decode_copy_paths(source, destination) {
        Ok((source, destination)) => copy_result(copy_file(&source, &destination)),
        Err(error) => copy_failure_result(error),
    }
}
#[no_mangle]
pub extern "C" fn hosted_path_copy_dir(
    source: UnixBytesOrUtf8OrWindowsU16s,
    destination: UnixBytesOrUtf8OrWindowsU16s,
    options: HostPathCopyDirArg2,
) -> HostPathCopyDirResult {
    match decode_copy_paths(source, destination) {
        Ok((source, destination)) => copy_result(copy_dir(
            &source,
            &destination,
            CopyOptions {
                preserve_links: matches!(options.symlinks, FollowOrPreserve::Preserve),
                merge: matches!(options.destination, MergeOrRequireNew::Merge),
            },
        )),
        Err(error) => copy_failure_result(error),
    }
}

fn native_path_result(result: io::Result<PathBuf>) -> HostPathAbsoluteResult {
    match result {
        Ok(path) => HostPathAbsoluteResult {
            tag: HostPathAbsoluteResultTag::Ok,
            payload: HostPathAbsoluteResultPayload {
                ok: ManuallyDrop::new(native_path_from_path(&path, roc_host())),
            },
        },
        Err(error) => HostPathAbsoluteResult {
            tag: HostPathAbsoluteResultTag::Err,
            payload: HostPathAbsoluteResultPayload {
                err: ManuallyDrop::new(dir_io_err_from_io(&error, roc_host())),
            },
        },
    }
}
#[no_mangle]
pub extern "C" fn hosted_path_absolute(
    path: UnixBytesOrUtf8OrWindowsU16s,
) -> HostPathAbsoluteResult {
    native_path_result(path_from_native(path, roc_host()).and_then(std::path::absolute))
}
#[no_mangle]
pub extern "C" fn hosted_path_canonicalize(
    path: UnixBytesOrUtf8OrWindowsU16s,
) -> HostPathCanonicalizeResult {
    native_path_result(path_from_native(path, roc_host()).and_then(fs::canonicalize))
}
#[no_mangle]
pub extern "C" fn hosted_env_create_temp_dir(
    parent: UnixBytesOrUtf8OrWindowsU16s,
    prefix: RocStr,
) -> HostEnvCreateTempDirResult {
    let result = path_from_native(parent, roc_host())
        .and_then(|parent| create_temp_dir(&parent, prefix.as_str()));
    unsafe {
        prefix.decref(roc_host());
    }
    native_path_result(result)
}
