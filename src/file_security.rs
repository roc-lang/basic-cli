//! Explicit regular-file access policies. Never substitute mode bits for ACLs.
use std::{fs::File, io, path::Path};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Policy {
    Default,
    OwnerOnly,
    PublicRead,
}

fn unsupported(message: &'static str) -> io::Error {
    io::Error::new(io::ErrorKind::Unsupported, message)
}

pub(crate) fn regular(file: &File) -> io::Result<()> {
    if file.metadata()?.is_file() {
        Ok(())
    } else {
        Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "permissions require a regular file",
        ))
    }
}

pub(crate) fn open_new(path: &Path, append: bool, policy: Policy) -> io::Result<File> {
    let file = native::create(path, append, policy).map_err(|error| {
        // Some native APIs report access denied for an existing directory or
        // link. Classify collisions here, before policy enforcement can fail
        // after this call has successfully created a new file.
        if path.symlink_metadata().is_ok() {
            io::Error::from(io::ErrorKind::AlreadyExists)
        } else {
            error
        }
    })?;
    regular(&file)?;
    if policy != Policy::Default {
        native::apply(&file, policy)?;
    }
    Ok(file)
}

pub(crate) fn set_permissions(path: &Path, policy: Policy) -> io::Result<()> {
    let file = native::open_existing(path)?;
    regular(&file)?;
    native::apply(&file, policy)
}

#[cfg(unix)]
fn mode(policy: Policy) -> u32 {
    match policy {
        Policy::OwnerOnly => 0o600,
        Policy::PublicRead => 0o644,
        Policy::Default => unreachable!("default is not an explicit policy"),
    }
}

#[cfg(target_os = "linux")]
mod native {
    use super::*;
    use std::{
        fs::{OpenOptions, Permissions},
        os::{
            fd::AsRawFd,
            unix::fs::{OpenOptionsExt, PermissionsExt},
        },
    };
    pub(super) fn create(path: &Path, append: bool, policy: Policy) -> io::Result<File> {
        let mut options = OpenOptions::new();
        options.write(true).append(append).create_new(true);
        if policy != Policy::Default {
            options.mode(0o600);
        }
        options.open(path)
    }
    pub(super) fn open_existing(path: &Path) -> io::Result<File> {
        match OpenOptions::new()
            .read(true)
            .custom_flags(libc::O_NONBLOCK)
            .open(path)
        {
            Err(error) if error.kind() == io::ErrorKind::PermissionDenied => {
                // A metadata handle lets the owner repair even a mode-000 file.
                OpenOptions::new()
                    .read(true)
                    .custom_flags(libc::O_PATH)
                    .open(path)
            }
            result => result,
        }
    }
    fn set_mode(file: &File, bits: u32) -> io::Result<()> {
        if unsafe { libc::fcntl(file.as_raw_fd(), libc::F_GETFL) } & libc::O_PATH != 0 {
            std::fs::set_permissions(
                format!("/proc/self/fd/{}", file.as_raw_fd()),
                Permissions::from_mode(bits),
            )
        } else {
            file.set_permissions(Permissions::from_mode(bits))
        }
    }

    pub(super) fn restrict_and_remove_acl(file: &File) -> io::Result<()> {
        // Removing an ACL preserves its mask as the owning group's mode bits.
        // Restrict that mask first so a previously denied group cannot gain
        // access during replacement, including when a later operation fails.
        set_mode(file, 0o600)?;
        if file.metadata()?.permissions().mode() & 0o7777 != 0o600 {
            return Err(unsupported("filesystem did not restrict file permissions"));
        }
        let key = c"system.posix_acl_access";
        // Linux's fd-based chmod/xattr APIs reject O_PATH descriptors. A
        // procfs magic link addresses the held inode, so a rename cannot
        // redirect this operation to another file.
        let metadata_handle =
            unsafe { libc::fcntl(file.as_raw_fd(), libc::F_GETFL) } & libc::O_PATH != 0;
        let proc_path = std::ffi::CString::new(format!("/proc/self/fd/{}", file.as_raw_fd()))
            .expect("numeric file descriptor");
        let result = unsafe {
            if metadata_handle {
                libc::removexattr(proc_path.as_ptr(), key.as_ptr())
            } else {
                libc::fremovexattr(file.as_raw_fd(), key.as_ptr())
            }
        };
        if result != 0 {
            let error = io::Error::last_os_error();
            if !matches!(error.raw_os_error(), Some(libc::ENODATA | libc::EOPNOTSUPP)) {
                return Err(error);
            }
        }
        // A named entry with no rights would deny PublicRead even with other=r.
        let size = unsafe {
            if metadata_handle {
                libc::getxattr(proc_path.as_ptr(), key.as_ptr(), std::ptr::null_mut(), 0)
            } else {
                libc::fgetxattr(file.as_raw_fd(), key.as_ptr(), std::ptr::null_mut(), 0)
            }
        };
        if size >= 0 {
            return Err(unsupported("filesystem retained an extended access ACL"));
        }
        let error = io::Error::last_os_error();
        if !matches!(error.raw_os_error(), Some(libc::ENODATA | libc::EOPNOTSUPP)) {
            return Err(error);
        }
        Ok(())
    }

    pub(super) fn apply(file: &File, policy: Policy) -> io::Result<()> {
        restrict_and_remove_acl(file)?;
        set_mode(file, mode(policy))?;
        if file.metadata()?.permissions().mode() & 0o7777 != mode(policy) {
            return Err(unsupported("filesystem did not enforce file permissions"));
        }
        Ok(())
    }
}

#[cfg(target_os = "macos")]
mod native {
    use super::*;
    use std::{
        ffi::{c_int, c_void, CString},
        fs::OpenOptions,
        os::{
            fd::{AsRawFd, FromRawFd},
            unix::{
                ffi::OsStrExt,
                fs::{OpenOptionsExt, PermissionsExt},
            },
        },
    };
    type Opaque = *mut c_void;
    extern "C" {
        fn filesec_init() -> Opaque;
        fn filesec_free(value: Opaque);
        fn filesec_set_property(value: Opaque, property: c_int, data: *const c_void) -> c_int;
        fn openx_np(path: *const libc::c_char, flags: c_int, security: Opaque) -> c_int;
        fn fchmodx_np(fd: c_int, security: Opaque) -> c_int;
        fn acl_init(count: c_int) -> Opaque;
        fn acl_free(value: Opaque) -> c_int;
        fn acl_get_flagset_np(value: Opaque, flags: *mut Opaque) -> c_int;
        fn acl_add_flag_np(flags: Opaque, flag: c_int) -> c_int;
        fn acl_get_fd(fd: c_int) -> Opaque;
        fn acl_get_entry(acl: Opaque, entry: c_int, result: *mut Opaque) -> c_int;
    }
    const NO_INHERIT: c_int = 1 << 17;
    struct Security {
        filesec: Opaque,
        acl: Opaque,
    }
    impl Drop for Security {
        fn drop(&mut self) {
            unsafe {
                filesec_free(self.filesec);
                acl_free(self.acl);
            }
        }
    }
    fn check(result: c_int) -> io::Result<()> {
        if result == 0 {
            Ok(())
        } else {
            Err(io::Error::last_os_error())
        }
    }
    impl Security {
        fn new(mode: u32) -> io::Result<Self> {
            let filesec = unsafe { filesec_init() };
            if filesec.is_null() {
                return Err(io::Error::last_os_error());
            }
            let acl = unsafe { acl_init(0) };
            if acl.is_null() {
                unsafe { filesec_free(filesec) };
                return Err(io::Error::last_os_error());
            }
            let security = Self { filesec, acl };
            let mut flags = std::ptr::null_mut();
            let bits = mode as libc::mode_t;
            unsafe {
                check(acl_get_flagset_np(acl, &mut flags))?;
                check(acl_add_flag_np(flags, NO_INHERIT))?;
                check(filesec_set_property(
                    filesec,
                    4,
                    (&bits as *const libc::mode_t).cast(),
                ))?;
                check(filesec_set_property(
                    filesec,
                    5,
                    (&acl as *const Opaque).cast(),
                ))?;
            }
            Ok(security)
        }
    }
    pub(super) fn create(path: &Path, append: bool, policy: Policy) -> io::Result<File> {
        if policy == Policy::Default {
            return OpenOptions::new()
                .write(true)
                .append(append)
                .create_new(true)
                .open(path);
        }
        let name = CString::new(path.as_os_str().as_bytes())?;
        let security = Security::new(0o600)?;
        let flags = libc::O_WRONLY
            | libc::O_CREAT
            | libc::O_EXCL
            | libc::O_CLOEXEC
            | if append { libc::O_APPEND } else { 0 };
        let fd = unsafe { openx_np(name.as_ptr(), flags, security.filesec) };
        if fd < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(unsafe { File::from_raw_fd(fd) })
    }
    pub(super) fn open_existing(path: &Path) -> io::Result<File> {
        OpenOptions::new()
            .read(true)
            .custom_flags(libc::O_NONBLOCK)
            .open(path)
    }
    pub(super) fn apply(file: &File, policy: Policy) -> io::Result<()> {
        let security = Security::new(mode(policy))?;
        unsafe {
            check(fchmodx_np(file.as_raw_fd(), security.filesec))?;
        }
        if file.metadata()?.permissions().mode() & 0o7777 != mode(policy) {
            return Err(unsupported("filesystem did not enforce file permissions"));
        }
        let acl = unsafe { acl_get_fd(file.as_raw_fd()) };
        if acl.is_null() {
            let error = io::Error::last_os_error();
            // Darwin reports an absent extended ACL with ENOENT. The
            // no-inherit creation flag need not remain stored on a file.
            return if error.raw_os_error() == Some(libc::ENOENT) {
                Ok(())
            } else {
                Err(error)
            };
        }
        let mut entry = std::ptr::null_mut();
        let valid = unsafe { acl_get_entry(acl, 0, &mut entry) != 0 };
        unsafe { acl_free(acl) };
        if !valid {
            return Err(unsupported(
                "filesystem did not enforce the replacement ACL",
            ));
        }
        Ok(())
    }
}

#[cfg(windows)]
mod native {
    use super::*;
    use std::{
        mem::{size_of, zeroed},
        os::windows::{
            ffi::OsStrExt,
            io::{AsRawHandle, FromRawHandle},
        },
        ptr::{null, null_mut},
    };
    use windows_sys::Win32::{
        Foundation::{CloseHandle, LocalFree, HANDLE, INVALID_HANDLE_VALUE},
        Security::{
            Authorization::{GetSecurityInfo, SetSecurityInfo, SE_FILE_OBJECT},
            *,
        },
        Storage::FileSystem::*,
        System::{
            SystemServices::{FILE_PERSISTENT_ACLS, SECURITY_DESCRIPTOR_REVISION},
            Threading::{GetCurrentProcess, OpenProcessToken},
        },
    };
    const OWNER_RIGHTS: u32 = FILE_GENERIC_READ | FILE_GENERIC_WRITE | READ_CONTROL | WRITE_DAC;
    fn wide_path(path: &Path) -> io::Result<Vec<u16>> {
        let mut name: Vec<u16> = path.as_os_str().encode_wide().collect();
        if name.contains(&0) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "file path contains a NUL character",
            ));
        }
        name.push(0);
        Ok(name)
    }
    fn check(value: i32) -> io::Result<()> {
        if value != 0 {
            Ok(())
        } else {
            Err(io::Error::last_os_error())
        }
    }
    struct Descriptor(PSECURITY_DESCRIPTOR);
    impl Drop for Descriptor {
        fn drop(&mut self) {
            unsafe {
                LocalFree(self.0);
            }
        }
    }
    struct Acl(Vec<u32>);
    impl Acl {
        fn new(owner: PSID, policy: Policy) -> io::Result<Self> {
            let mut everyone = [0u32; 17];
            let mut sid_size = std::mem::size_of_val(&everyone) as u32;
            unsafe {
                check(CreateWellKnownSid(
                    WinWorldSid,
                    null_mut(),
                    everyone.as_mut_ptr().cast(),
                    &mut sid_size,
                ))?;
            }
            let owner_size = unsafe { GetLengthSid(owner) };
            let bytes = size_of::<ACL>()
                + 2 * (size_of::<ACCESS_ALLOWED_ACE>() - 4)
                + owner_size as usize
                + sid_size as usize;
            let mut acl = Self(vec![0; bytes.div_ceil(4)]);
            unsafe {
                check(InitializeAcl(
                    acl.ptr(),
                    (acl.0.len() * 4) as u32,
                    ACL_REVISION,
                ))?;
                check(AddAccessAllowedAce(
                    acl.ptr(),
                    ACL_REVISION,
                    OWNER_RIGHTS,
                    owner,
                ))?;
                if policy == Policy::PublicRead {
                    check(AddAccessAllowedAce(
                        acl.ptr(),
                        ACL_REVISION,
                        FILE_GENERIC_READ,
                        everyone.as_mut_ptr().cast(),
                    ))?;
                }
            }
            Ok(acl)
        }
        fn ptr(&mut self) -> *mut ACL {
            self.0.as_mut_ptr().cast()
        }
    }
    fn persistent(file: &File) -> io::Result<()> {
        let mut flags = 0;
        unsafe {
            check(GetVolumeInformationByHandleW(
                file.as_raw_handle(),
                null_mut(),
                0,
                null_mut(),
                null_mut(),
                &mut flags,
                null_mut(),
                0,
            ))?;
        }
        if flags & FILE_PERSISTENT_ACLS == 0 {
            return Err(unsupported("filesystem has no persistent ACL support"));
        }
        Ok(())
    }
    fn owner(file: &File) -> io::Result<(PSID, Descriptor)> {
        let mut sid = null_mut();
        let mut descriptor = null_mut();
        let code = unsafe {
            GetSecurityInfo(
                file.as_raw_handle(),
                SE_FILE_OBJECT,
                OWNER_SECURITY_INFORMATION,
                &mut sid,
                null_mut(),
                null_mut(),
                null_mut(),
                &mut descriptor,
            )
        };
        if code != 0 {
            return Err(io::Error::from_raw_os_error(code as i32));
        }
        Ok((sid, Descriptor(descriptor)))
    }
    pub(super) fn open_existing(path: &Path) -> io::Result<File> {
        let name = wide_path(path)?;
        let handle = unsafe {
            CreateFileW(
                name.as_ptr(),
                READ_CONTROL | WRITE_DAC | FILE_READ_ATTRIBUTES,
                FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                null(),
                OPEN_EXISTING,
                FILE_FLAG_BACKUP_SEMANTICS,
                null_mut(),
            )
        };
        if handle == INVALID_HANDLE_VALUE {
            return Err(io::Error::last_os_error());
        }
        Ok(unsafe { File::from_raw_handle(handle) })
    }
    pub(super) fn create(path: &Path, append: bool, policy: Policy) -> io::Result<File> {
        if policy == Policy::Default {
            return std::fs::OpenOptions::new()
                .write(true)
                .append(append)
                .create_new(true)
                .open(path);
        }
        let name = wide_path(path)?;
        // Alternate data streams share their base file's descriptor. Treating
        // a newly-created stream as a new private file could change an existing
        // file's ACL, contrary to creation-only policy semantics.
        if path.components().any(|component| matches!(component,
            std::path::Component::Normal(name) if name.encode_wide().any(|unit| unit == u16::from(b':')))) {
            return Err(io::Error::new(io::ErrorKind::InvalidInput,
                "explicit creation permissions require a file, not an alternate data stream"));
        }
        let mut token: HANDLE = null_mut();
        unsafe {
            check(OpenProcessToken(
                GetCurrentProcess(),
                TOKEN_QUERY,
                &mut token,
            ))?;
        }
        let mut length = 0;
        unsafe {
            GetTokenInformation(token, TokenUser, null_mut(), 0, &mut length);
        }
        let mut storage = vec![0usize; (length as usize).div_ceil(size_of::<usize>())];
        let result = unsafe {
            GetTokenInformation(
                token,
                TokenUser,
                storage.as_mut_ptr().cast(),
                length,
                &mut length,
            )
        };
        unsafe { CloseHandle(token) };
        check(result)?;
        let sid = unsafe { (*(storage.as_ptr().cast::<TOKEN_USER>())).User.Sid };
        let mut acl = Acl::new(sid, Policy::OwnerOnly)?;
        let mut descriptor: SECURITY_DESCRIPTOR = unsafe { zeroed() };
        unsafe {
            check(InitializeSecurityDescriptor(
                (&mut descriptor as *mut SECURITY_DESCRIPTOR).cast(),
                SECURITY_DESCRIPTOR_REVISION,
            ))?;
            check(SetSecurityDescriptorOwner(
                (&mut descriptor as *mut SECURITY_DESCRIPTOR).cast(),
                sid,
                0,
            ))?;
            check(SetSecurityDescriptorDacl(
                (&mut descriptor as *mut SECURITY_DESCRIPTOR).cast(),
                1,
                acl.ptr(),
                0,
            ))?;
            check(SetSecurityDescriptorControl(
                (&mut descriptor as *mut SECURITY_DESCRIPTOR).cast(),
                SE_DACL_PROTECTED,
                SE_DACL_PROTECTED,
            ))?;
        }
        let attributes = SECURITY_ATTRIBUTES {
            nLength: size_of::<SECURITY_ATTRIBUTES>() as u32,
            lpSecurityDescriptor: (&mut descriptor as *mut SECURITY_DESCRIPTOR).cast(),
            bInheritHandle: 0,
        };
        let access = if append {
            FILE_APPEND_DATA | FILE_READ_ATTRIBUTES
        } else {
            FILE_GENERIC_WRITE
        };
        let handle = unsafe {
            CreateFileW(
                name.as_ptr(),
                access | READ_CONTROL | WRITE_DAC | FILE_READ_ATTRIBUTES,
                FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                &attributes,
                CREATE_NEW,
                FILE_ATTRIBUTE_NORMAL,
                null_mut(),
            )
        };
        if handle == INVALID_HANDLE_VALUE {
            return Err(io::Error::last_os_error());
        }
        Ok(unsafe { File::from_raw_handle(handle) })
    }
    pub(super) fn apply(file: &File, policy: Policy) -> io::Result<()> {
        persistent(file)?;
        let (sid, _owner) = owner(file)?;
        let mut acl = Acl::new(sid, policy)?;
        let code = unsafe {
            SetSecurityInfo(
                file.as_raw_handle(),
                SE_FILE_OBJECT,
                DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION,
                null_mut(),
                null_mut(),
                acl.ptr(),
                null(),
            )
        };
        if code != 0 {
            return Err(io::Error::from_raw_os_error(code as i32));
        }
        let mut actual = null_mut();
        let mut descriptor = null_mut();
        let code = unsafe {
            GetSecurityInfo(
                file.as_raw_handle(),
                SE_FILE_OBJECT,
                DACL_SECURITY_INFORMATION,
                null_mut(),
                null_mut(),
                &mut actual,
                null_mut(),
                &mut descriptor,
            )
        };
        if code != 0 {
            return Err(io::Error::from_raw_os_error(code as i32));
        }
        let descriptor = Descriptor(descriptor);
        let mut control = 0;
        let mut revision = 0;
        unsafe {
            check(GetSecurityDescriptorControl(
                descriptor.0,
                &mut control,
                &mut revision,
            ))?;
        }
        if actual.is_null() || control & SE_DACL_PROTECTED == 0 {
            return Err(unsupported("filesystem did not protect the ACL"));
        }
        let expected = unsafe { &*acl.ptr() };
        let actual = unsafe { &*actual };
        if actual.AceCount != expected.AceCount {
            return Err(unsupported("filesystem changed the requested ACL"));
        }
        // Compare every ACE, including its SID, mask, type and inheritance flags.
        for index in 0..u32::from(actual.AceCount) {
            let mut a = null_mut();
            let mut b = null_mut();
            unsafe {
                check(GetAce(actual, index, &mut a))?;
                check(GetAce(expected, index, &mut b))?;
                let len = usize::from((*(b.cast::<ACE_HEADER>())).AceSize);
                if usize::from((*(a.cast::<ACE_HEADER>())).AceSize) != len {
                    return Err(unsupported("filesystem changed an access entry"));
                }
                if std::slice::from_raw_parts(a.cast::<u8>(), len)
                    != std::slice::from_raw_parts(b.cast::<u8>(), len)
                {
                    return Err(unsupported("filesystem changed a requested access grant"));
                }
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    #[cfg(target_os = "linux")]
    #[test]
    fn owner_can_restore_access_to_a_mode_zero_file() {
        use std::os::unix::fs::PermissionsExt;
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("inaccessible");
        std::fs::write(&path, b"preserved").unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o000)).unwrap();
        let result = set_permissions(&path, Policy::OwnerOnly);
        // Restore access even if the assertion fails, so cleanup can succeed.
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).unwrap();
        result.unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"preserved");
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn metadata_handle_permissions_follow_the_held_inode_after_rename() {
        use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
        let directory = tempfile::tempdir().unwrap();
        let original = directory.path().join("original");
        let moved = directory.path().join("moved");
        std::fs::write(&original, b"held").unwrap();
        let file = std::fs::OpenOptions::new()
            .read(true)
            .custom_flags(libc::O_PATH)
            .open(&original)
            .unwrap();
        std::fs::rename(&original, &moved).unwrap();
        std::fs::write(&original, b"replacement").unwrap();
        std::fs::set_permissions(&original, std::fs::Permissions::from_mode(0o644)).unwrap();
        native::apply(&file, Policy::OwnerOnly).unwrap();
        assert_eq!(
            std::fs::metadata(&moved).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert_eq!(
            std::fs::metadata(&original).unwrap().permissions().mode() & 0o777,
            0o644
        );
    }

    #[cfg(windows)]
    #[test]
    fn embedded_nul_paths_do_not_create_or_change_a_truncated_target() {
        let directory = tempfile::tempdir().unwrap();
        let target = directory.path().join("target");
        let invalid = directory.path().join("target\0suffix");
        assert_eq!(
            open_new(&invalid, false, Policy::OwnerOnly)
                .unwrap_err()
                .kind(),
            io::ErrorKind::InvalidInput
        );
        assert!(!target.exists());
        std::fs::write(&target, b"preserved").unwrap();
        assert_eq!(
            set_permissions(&invalid, Policy::OwnerOnly)
                .unwrap_err()
                .kind(),
            io::ErrorKind::InvalidInput
        );
        assert_eq!(std::fs::read(&target).unwrap(), b"preserved");
    }

    #[test]
    fn explicit_policies_preserve_contents_and_require_regular_files() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("secret");
        let mut file = open_new(&path, false, Policy::OwnerOnly).unwrap();
        file.write_all(b"secret").unwrap();
        drop(file);
        set_permissions(&path, Policy::PublicRead).unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"secret");
        set_permissions(&path, Policy::OwnerOnly).unwrap();
        assert!(set_permissions(dir.path(), Policy::OwnerOnly).is_err());
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                std::fs::metadata(path).unwrap().permissions().mode() & 0o7777,
                0o600
            );
        }
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn restrictive_creation_does_not_inherit_parent_access_grants() {
        use std::os::fd::AsRawFd;
        extern "C" {
            fn acl_get_fd(fd: i32) -> *mut std::ffi::c_void;
            fn acl_get_entry(
                acl: *mut std::ffi::c_void,
                entry: i32,
                result: *mut *mut std::ffi::c_void,
            ) -> i32;
            fn acl_free(acl: *mut std::ffi::c_void) -> i32;
        }
        let directory = tempfile::tempdir().unwrap();
        let result = std::process::Command::new("/bin/chmod")
            .args([
                "+a",
                "everyone allow read,write,execute,file_inherit,directory_inherit",
            ])
            .arg(directory.path())
            .status()
            .unwrap();
        assert!(result.success());
        // Inspect immediately after the creation primitive, before apply can
        // remove grants: this specifically guards the creation-time window.
        let file =
            native::create(&directory.path().join("private"), false, Policy::OwnerOnly).unwrap();
        let acl = unsafe { acl_get_fd(file.as_raw_fd()) };
        if acl.is_null() {
            assert_eq!(
                io::Error::last_os_error().raw_os_error(),
                Some(libc::ENOENT)
            );
        } else {
            let mut entry = std::ptr::null_mut();
            assert_ne!(unsafe { acl_get_entry(acl, 0, &mut entry) }, 0);
            unsafe { acl_free(acl) };
        }
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn acl_removal_never_exposes_the_mask_to_a_previously_denied_group() {
        use std::os::{
            fd::AsRawFd,
            unix::fs::{OpenOptionsExt, PermissionsExt},
        };
        for metadata_handle in [false, true] {
            let directory = tempfile::tempdir().unwrap();
            let path = directory.path().join("private");
            let file = std::fs::File::create(&path).unwrap();
            let mut acl = 2u32.to_le_bytes().to_vec();
            // The named user has rw, but the owning group has no access.
            // Removing this ACL without restricting its mask exposes rw to
            // the owning group even though that group was previously denied.
            for (tag, permissions, id) in [
                (1u16, 6u16, u32::MAX),
                (2, 6, unsafe { libc::geteuid() }.wrapping_add(1)),
                (4, 0, u32::MAX),
                (16, 6, u32::MAX),
                (32, 0, u32::MAX),
            ] {
                acl.extend(tag.to_le_bytes());
                acl.extend(permissions.to_le_bytes());
                acl.extend(id.to_le_bytes());
            }
            assert_eq!(
                unsafe {
                    libc::fsetxattr(
                        file.as_raw_fd(),
                        c"system.posix_acl_access".as_ptr(),
                        acl.as_ptr().cast(),
                        acl.len(),
                        0,
                    )
                },
                0,
                "{}",
                io::Error::last_os_error()
            );
            assert_eq!(file.metadata().unwrap().permissions().mode() & 0o777, 0o660);
            let file = if metadata_handle {
                std::fs::OpenOptions::new()
                    .read(true)
                    .custom_flags(libc::O_PATH)
                    .open(&path)
                    .unwrap()
            } else {
                file
            };
            // Inspect the actual intermediate state, before final chmod. A
            // failure here must leave no non-owner access, for either handle.
            native::restrict_and_remove_acl(&file).unwrap();
            assert_eq!(file.metadata().unwrap().permissions().mode() & 0o777, 0o600);
            let ordinary = std::fs::File::open(&path).unwrap();
            assert_eq!(
                unsafe {
                    libc::fgetxattr(
                        ordinary.as_raw_fd(),
                        c"system.posix_acl_access".as_ptr(),
                        std::ptr::null_mut(),
                        0,
                    )
                },
                -1
            );
            assert_eq!(
                io::Error::last_os_error().raw_os_error(),
                Some(libc::ENODATA)
            );
            native::apply(&file, Policy::PublicRead).unwrap();
            assert_eq!(file.metadata().unwrap().permissions().mode() & 0o777, 0o644);
        }
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn extended_acl_denials_do_not_survive_public_read() {
        use std::os::{fd::AsRawFd, unix::ffi::OsStrExt};
        let directory = tempfile::tempdir().unwrap();
        // A named user with no permissions takes precedence over other=r.
        let mut acl = 2u32.to_le_bytes().to_vec();
        for (tag, permissions, id) in [
            (1u16, 7u16, u32::MAX),
            (2, 0, unsafe { libc::geteuid() }.wrapping_add(1)),
            (4, 7, u32::MAX),
            (16, 7, u32::MAX),
            (32, 7, u32::MAX),
        ] {
            acl.extend(tag.to_le_bytes());
            acl.extend(permissions.to_le_bytes());
            acl.extend(id.to_le_bytes());
        }
        let path = std::ffi::CString::new(directory.path().as_os_str().as_bytes()).unwrap();
        assert_eq!(
            unsafe {
                libc::setxattr(
                    path.as_ptr(),
                    c"system.posix_acl_default".as_ptr(),
                    acl.as_ptr().cast(),
                    acl.len(),
                    0,
                )
            },
            0,
            "{}",
            io::Error::last_os_error()
        );
        let path = directory.path().join("public");
        let file = open_new(&path, false, Policy::PublicRead).unwrap();
        let result = unsafe {
            libc::fgetxattr(
                file.as_raw_fd(),
                c"system.posix_acl_access".as_ptr(),
                std::ptr::null_mut(),
                0,
            )
        };
        assert_eq!(result, -1);
        assert_eq!(
            io::Error::last_os_error().raw_os_error(),
            Some(libc::ENODATA)
        );
    }
}
