#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(u8)]
pub enum discriminant_IOError {
    AddrInUse = 0,
    AddrNotAvailable = 1,
    AlreadyExists = 2,
    ArgumentListTooLong = 3,
    BrokenPipe = 4,
    ConnectionAborted = 5,
    ConnectionRefused = 6,
    ConnectionReset = 7,
    CrossesDevices = 8,
    Deadlock = 9,
    DirectoryNotEmpty = 10,
    ExecutableFileBusy = 11,
    FileTooLarge = 12,
    FilesystemLoop = 13,
    FilesystemQuotaExceeded = 14,
    HostUnreachable = 15,
    Interrupted = 16,
    InvalidData = 17,
    InvalidFilename = 18,
    InvalidInput = 19,
    IsADirectory = 20,
    NetworkDown = 21,
    NetworkUnreachable = 22,
    NotADirectory = 23,
    NotConnected = 24,
    NotFound = 25,
    NotSeekable = 26,
    Other = 27,
    OutOfMemory = 28,
    PermissionDenied = 29,
    ReadOnlyFilesystem = 30,
    ResourceBusy = 31,
    StaleNetworkFileHandle = 32,
    StorageFull = 33,
    TimedOut = 34,
    TooManyLinks = 35,
    UnexpectedEof = 36,
    Unsupported = 37,
    WouldBlock = 38,
    WriteZero = 39,
}

impl core::fmt::Debug for discriminant_IOError {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::AddrInUse => f.write_str("discriminant_IOError::AddrInUse"),
            Self::AddrNotAvailable => f.write_str("discriminant_IOError::AddrNotAvailable"),
            Self::AlreadyExists => f.write_str("discriminant_IOError::AlreadyExists"),
            Self::ArgumentListTooLong => f.write_str("discriminant_IOError::ArgumentListTooLong"),
            Self::BrokenPipe => f.write_str("discriminant_IOError::BrokenPipe"),
            Self::ConnectionAborted => f.write_str("discriminant_IOError::ConnectionAborted"),
            Self::ConnectionRefused => f.write_str("discriminant_IOError::ConnectionRefused"),
            Self::ConnectionReset => f.write_str("discriminant_IOError::ConnectionReset"),
            Self::CrossesDevices => f.write_str("discriminant_IOError::CrossesDevices"),
            Self::Deadlock => f.write_str("discriminant_IOError::Deadlock"),
            Self::DirectoryNotEmpty => f.write_str("discriminant_IOError::DirectoryNotEmpty"),
            Self::ExecutableFileBusy => f.write_str("discriminant_IOError::ExecutableFileBusy"),
            Self::FileTooLarge => f.write_str("discriminant_IOError::FileTooLarge"),
            Self::FilesystemLoop => f.write_str("discriminant_IOError::FilesystemLoop"),
            Self::FilesystemQuotaExceeded => {
                f.write_str("discriminant_IOError::FilesystemQuotaExceeded")
            }
            Self::HostUnreachable => f.write_str("discriminant_IOError::HostUnreachable"),
            Self::Interrupted => f.write_str("discriminant_IOError::Interrupted"),
            Self::InvalidData => f.write_str("discriminant_IOError::InvalidData"),
            Self::InvalidFilename => f.write_str("discriminant_IOError::InvalidFilename"),
            Self::InvalidInput => f.write_str("discriminant_IOError::InvalidInput"),
            Self::IsADirectory => f.write_str("discriminant_IOError::IsADirectory"),
            Self::NetworkDown => f.write_str("discriminant_IOError::NetworkDown"),
            Self::NetworkUnreachable => f.write_str("discriminant_IOError::NetworkUnreachable"),
            Self::NotADirectory => f.write_str("discriminant_IOError::NotADirectory"),
            Self::NotConnected => f.write_str("discriminant_IOError::NotConnected"),
            Self::NotFound => f.write_str("discriminant_IOError::NotFound"),
            Self::NotSeekable => f.write_str("discriminant_IOError::NotSeekable"),
            Self::Other => f.write_str("discriminant_IOError::Other"),
            Self::OutOfMemory => f.write_str("discriminant_IOError::OutOfMemory"),
            Self::PermissionDenied => f.write_str("discriminant_IOError::PermissionDenied"),
            Self::ReadOnlyFilesystem => f.write_str("discriminant_IOError::ReadOnlyFilesystem"),
            Self::ResourceBusy => f.write_str("discriminant_IOError::ResourceBusy"),
            Self::StaleNetworkFileHandle => {
                f.write_str("discriminant_IOError::StaleNetworkFileHandle")
            }
            Self::StorageFull => f.write_str("discriminant_IOError::StorageFull"),
            Self::TimedOut => f.write_str("discriminant_IOError::TimedOut"),
            Self::TooManyLinks => f.write_str("discriminant_IOError::TooManyLinks"),
            Self::UnexpectedEof => f.write_str("discriminant_IOError::UnexpectedEof"),
            Self::Unsupported => f.write_str("discriminant_IOError::Unsupported"),
            Self::WouldBlock => f.write_str("discriminant_IOError::WouldBlock"),
            Self::WriteZero => f.write_str("discriminant_IOError::WriteZero"),
        }
    }
}

#[repr(C, align(1))]
pub union union_IOError {
    AddrInUse: (),
    AddrNotAvailable: (),
    AlreadyExists: (),
    ArgumentListTooLong: (),
    BrokenPipe: (),
    ConnectionAborted: (),
    ConnectionRefused: (),
    ConnectionReset: (),
    CrossesDevices: (),
    Deadlock: (),
    DirectoryNotEmpty: (),
    ExecutableFileBusy: (),
    FileTooLarge: (),
    FilesystemLoop: (),
    FilesystemQuotaExceeded: (),
    HostUnreachable: (),
    Interrupted: (),
    InvalidData: (),
    InvalidFilename: (),
    InvalidInput: (),
    IsADirectory: (),
    NetworkDown: (),
    NetworkUnreachable: (),
    NotADirectory: (),
    NotConnected: (),
    NotFound: (),
    NotSeekable: (),
    Other: (),
    OutOfMemory: (),
    PermissionDenied: (),
    ReadOnlyFilesystem: (),
    ResourceBusy: (),
    StaleNetworkFileHandle: (),
    StorageFull: (),
    TimedOut: (),
    TooManyLinks: (),
    UnexpectedEof: (),
    Unsupported: (),
    WouldBlock: (),
    WriteZero: (),
}

// const _SIZE_CHECK_union_IOError: () = assert!(core::mem::size_of::<union_IOError>() == 1);
const _ALIGN_CHECK_union_IOError: () = assert!(core::mem::align_of::<union_IOError>() == 1);

const _SIZE_CHECK_IOError: () = assert!(core::mem::size_of::<IOError>() == 1);
const _ALIGN_CHECK_IOError: () = assert!(core::mem::align_of::<IOError>() == 1);

impl IOError {
    /// Returns which variant this tag union holds. Note that this never includes a payload!
    pub fn discriminant(&self) -> discriminant_IOError {
        unsafe {
            let bytes = core::mem::transmute::<&Self, &[u8; core::mem::size_of::<Self>()]>(self);

            core::mem::transmute::<u8, discriminant_IOError>(*bytes.as_ptr().add(0))
        }
    }

    /// Internal helper
    fn set_discriminant(&mut self, discriminant: discriminant_IOError) {
        let discriminant_ptr: *mut discriminant_IOError = (self as *mut IOError).cast();

        unsafe {
            *(discriminant_ptr.add(0)) = discriminant;
        }
    }
}

#[repr(C)]
pub struct IOError {
    payload: union_IOError,
    discriminant: discriminant_IOError,
}

impl Clone for IOError {
    fn clone(&self) -> Self {
        use discriminant_IOError::*;

        let payload = unsafe {
            match self.discriminant {
                AddrInUse => union_IOError {
                    AddrInUse: self.payload.AddrInUse.clone(),
                },
                AddrNotAvailable => union_IOError {
                    AddrNotAvailable: self.payload.AddrNotAvailable.clone(),
                },
                AlreadyExists => union_IOError {
                    AlreadyExists: self.payload.AlreadyExists.clone(),
                },
                ArgumentListTooLong => union_IOError {
                    ArgumentListTooLong: self.payload.ArgumentListTooLong.clone(),
                },
                BrokenPipe => union_IOError {
                    BrokenPipe: self.payload.BrokenPipe.clone(),
                },
                ConnectionAborted => union_IOError {
                    ConnectionAborted: self.payload.ConnectionAborted.clone(),
                },
                ConnectionRefused => union_IOError {
                    ConnectionRefused: self.payload.ConnectionRefused.clone(),
                },
                ConnectionReset => union_IOError {
                    ConnectionReset: self.payload.ConnectionReset.clone(),
                },
                CrossesDevices => union_IOError {
                    CrossesDevices: self.payload.CrossesDevices.clone(),
                },
                Deadlock => union_IOError {
                    Deadlock: self.payload.Deadlock.clone(),
                },
                DirectoryNotEmpty => union_IOError {
                    DirectoryNotEmpty: self.payload.DirectoryNotEmpty.clone(),
                },
                ExecutableFileBusy => union_IOError {
                    ExecutableFileBusy: self.payload.ExecutableFileBusy.clone(),
                },
                FileTooLarge => union_IOError {
                    FileTooLarge: self.payload.FileTooLarge.clone(),
                },
                FilesystemLoop => union_IOError {
                    FilesystemLoop: self.payload.FilesystemLoop.clone(),
                },
                FilesystemQuotaExceeded => union_IOError {
                    FilesystemQuotaExceeded: self.payload.FilesystemQuotaExceeded.clone(),
                },
                HostUnreachable => union_IOError {
                    HostUnreachable: self.payload.HostUnreachable.clone(),
                },
                Interrupted => union_IOError {
                    Interrupted: self.payload.Interrupted.clone(),
                },
                InvalidData => union_IOError {
                    InvalidData: self.payload.InvalidData.clone(),
                },
                InvalidFilename => union_IOError {
                    InvalidFilename: self.payload.InvalidFilename.clone(),
                },
                InvalidInput => union_IOError {
                    InvalidInput: self.payload.InvalidInput.clone(),
                },
                IsADirectory => union_IOError {
                    IsADirectory: self.payload.IsADirectory.clone(),
                },
                NetworkDown => union_IOError {
                    NetworkDown: self.payload.NetworkDown.clone(),
                },
                NetworkUnreachable => union_IOError {
                    NetworkUnreachable: self.payload.NetworkUnreachable.clone(),
                },
                NotADirectory => union_IOError {
                    NotADirectory: self.payload.NotADirectory.clone(),
                },
                NotConnected => union_IOError {
                    NotConnected: self.payload.NotConnected.clone(),
                },
                NotFound => union_IOError {
                    NotFound: self.payload.NotFound.clone(),
                },
                NotSeekable => union_IOError {
                    NotSeekable: self.payload.NotSeekable.clone(),
                },
                Other => union_IOError {
                    Other: self.payload.Other.clone(),
                },
                OutOfMemory => union_IOError {
                    OutOfMemory: self.payload.OutOfMemory.clone(),
                },
                PermissionDenied => union_IOError {
                    PermissionDenied: self.payload.PermissionDenied.clone(),
                },
                ReadOnlyFilesystem => union_IOError {
                    ReadOnlyFilesystem: self.payload.ReadOnlyFilesystem.clone(),
                },
                ResourceBusy => union_IOError {
                    ResourceBusy: self.payload.ResourceBusy.clone(),
                },
                StaleNetworkFileHandle => union_IOError {
                    StaleNetworkFileHandle: self.payload.StaleNetworkFileHandle.clone(),
                },
                StorageFull => union_IOError {
                    StorageFull: self.payload.StorageFull.clone(),
                },
                TimedOut => union_IOError {
                    TimedOut: self.payload.TimedOut.clone(),
                },
                TooManyLinks => union_IOError {
                    TooManyLinks: self.payload.TooManyLinks.clone(),
                },
                UnexpectedEof => union_IOError {
                    UnexpectedEof: self.payload.UnexpectedEof.clone(),
                },
                Unsupported => union_IOError {
                    Unsupported: self.payload.Unsupported.clone(),
                },
                WouldBlock => union_IOError {
                    WouldBlock: self.payload.WouldBlock.clone(),
                },
                WriteZero => union_IOError {
                    WriteZero: self.payload.WriteZero.clone(),
                },
            }
        };

        Self {
            discriminant: self.discriminant,
            payload,
        }
    }
}

impl core::fmt::Debug for IOError {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        use discriminant_IOError::*;

        unsafe {
            match self.discriminant {
                AddrInUse => {
                    let field: &() = &self.payload.AddrInUse;
                    f.debug_tuple("IOError::AddrInUse").field(field).finish()
                }
                AddrNotAvailable => {
                    let field: &() = &self.payload.AddrNotAvailable;
                    f.debug_tuple("IOError::AddrNotAvailable")
                        .field(field)
                        .finish()
                }
                AlreadyExists => {
                    let field: &() = &self.payload.AlreadyExists;
                    f.debug_tuple("IOError::AlreadyExists")
                        .field(field)
                        .finish()
                }
                ArgumentListTooLong => {
                    let field: &() = &self.payload.ArgumentListTooLong;
                    f.debug_tuple("IOError::ArgumentListTooLong")
                        .field(field)
                        .finish()
                }
                BrokenPipe => {
                    let field: &() = &self.payload.BrokenPipe;
                    f.debug_tuple("IOError::BrokenPipe").field(field).finish()
                }
                ConnectionAborted => {
                    let field: &() = &self.payload.ConnectionAborted;
                    f.debug_tuple("IOError::ConnectionAborted")
                        .field(field)
                        .finish()
                }
                ConnectionRefused => {
                    let field: &() = &self.payload.ConnectionRefused;
                    f.debug_tuple("IOError::ConnectionRefused")
                        .field(field)
                        .finish()
                }
                ConnectionReset => {
                    let field: &() = &self.payload.ConnectionReset;
                    f.debug_tuple("IOError::ConnectionReset")
                        .field(field)
                        .finish()
                }
                CrossesDevices => {
                    let field: &() = &self.payload.CrossesDevices;
                    f.debug_tuple("IOError::CrossesDevices")
                        .field(field)
                        .finish()
                }
                Deadlock => {
                    let field: &() = &self.payload.Deadlock;
                    f.debug_tuple("IOError::Deadlock").field(field).finish()
                }
                DirectoryNotEmpty => {
                    let field: &() = &self.payload.DirectoryNotEmpty;
                    f.debug_tuple("IOError::DirectoryNotEmpty")
                        .field(field)
                        .finish()
                }
                ExecutableFileBusy => {
                    let field: &() = &self.payload.ExecutableFileBusy;
                    f.debug_tuple("IOError::ExecutableFileBusy")
                        .field(field)
                        .finish()
                }
                FileTooLarge => {
                    let field: &() = &self.payload.FileTooLarge;
                    f.debug_tuple("IOError::FileTooLarge").field(field).finish()
                }
                FilesystemLoop => {
                    let field: &() = &self.payload.FilesystemLoop;
                    f.debug_tuple("IOError::FilesystemLoop")
                        .field(field)
                        .finish()
                }
                FilesystemQuotaExceeded => {
                    let field: &() = &self.payload.FilesystemQuotaExceeded;
                    f.debug_tuple("IOError::FilesystemQuotaExceeded")
                        .field(field)
                        .finish()
                }
                HostUnreachable => {
                    let field: &() = &self.payload.HostUnreachable;
                    f.debug_tuple("IOError::HostUnreachable")
                        .field(field)
                        .finish()
                }
                Interrupted => {
                    let field: &() = &self.payload.Interrupted;
                    f.debug_tuple("IOError::Interrupted").field(field).finish()
                }
                InvalidData => {
                    let field: &() = &self.payload.InvalidData;
                    f.debug_tuple("IOError::InvalidData").field(field).finish()
                }
                InvalidFilename => {
                    let field: &() = &self.payload.InvalidFilename;
                    f.debug_tuple("IOError::InvalidFilename")
                        .field(field)
                        .finish()
                }
                InvalidInput => {
                    let field: &() = &self.payload.InvalidInput;
                    f.debug_tuple("IOError::InvalidInput").field(field).finish()
                }
                IsADirectory => {
                    let field: &() = &self.payload.IsADirectory;
                    f.debug_tuple("IOError::IsADirectory").field(field).finish()
                }
                NetworkDown => {
                    let field: &() = &self.payload.NetworkDown;
                    f.debug_tuple("IOError::NetworkDown").field(field).finish()
                }
                NetworkUnreachable => {
                    let field: &() = &self.payload.NetworkUnreachable;
                    f.debug_tuple("IOError::NetworkUnreachable")
                        .field(field)
                        .finish()
                }
                NotADirectory => {
                    let field: &() = &self.payload.NotADirectory;
                    f.debug_tuple("IOError::NotADirectory")
                        .field(field)
                        .finish()
                }
                NotConnected => {
                    let field: &() = &self.payload.NotConnected;
                    f.debug_tuple("IOError::NotConnected").field(field).finish()
                }
                NotFound => {
                    let field: &() = &self.payload.NotFound;
                    f.debug_tuple("IOError::NotFound").field(field).finish()
                }
                NotSeekable => {
                    let field: &() = &self.payload.NotSeekable;
                    f.debug_tuple("IOError::NotSeekable").field(field).finish()
                }
                Other => {
                    let field: &() = &self.payload.Other;
                    f.debug_tuple("IOError::Other").field(field).finish()
                }
                OutOfMemory => {
                    let field: &() = &self.payload.OutOfMemory;
                    f.debug_tuple("IOError::OutOfMemory").field(field).finish()
                }
                PermissionDenied => {
                    let field: &() = &self.payload.PermissionDenied;
                    f.debug_tuple("IOError::PermissionDenied")
                        .field(field)
                        .finish()
                }
                ReadOnlyFilesystem => {
                    let field: &() = &self.payload.ReadOnlyFilesystem;
                    f.debug_tuple("IOError::ReadOnlyFilesystem")
                        .field(field)
                        .finish()
                }
                ResourceBusy => {
                    let field: &() = &self.payload.ResourceBusy;
                    f.debug_tuple("IOError::ResourceBusy").field(field).finish()
                }
                StaleNetworkFileHandle => {
                    let field: &() = &self.payload.StaleNetworkFileHandle;
                    f.debug_tuple("IOError::StaleNetworkFileHandle")
                        .field(field)
                        .finish()
                }
                StorageFull => {
                    let field: &() = &self.payload.StorageFull;
                    f.debug_tuple("IOError::StorageFull").field(field).finish()
                }
                TimedOut => {
                    let field: &() = &self.payload.TimedOut;
                    f.debug_tuple("IOError::TimedOut").field(field).finish()
                }
                TooManyLinks => {
                    let field: &() = &self.payload.TooManyLinks;
                    f.debug_tuple("IOError::TooManyLinks").field(field).finish()
                }
                UnexpectedEof => {
                    let field: &() = &self.payload.UnexpectedEof;
                    f.debug_tuple("IOError::UnexpectedEof")
                        .field(field)
                        .finish()
                }
                Unsupported => {
                    let field: &() = &self.payload.Unsupported;
                    f.debug_tuple("IOError::Unsupported").field(field).finish()
                }
                WouldBlock => {
                    let field: &() = &self.payload.WouldBlock;
                    f.debug_tuple("IOError::WouldBlock").field(field).finish()
                }
                WriteZero => {
                    let field: &() = &self.payload.WriteZero;
                    f.debug_tuple("IOError::WriteZero").field(field).finish()
                }
            }
        }
    }
}

impl Eq for IOError {}

impl PartialEq for IOError {
    fn eq(&self, other: &Self) -> bool {
        use discriminant_IOError::*;

        if self.discriminant != other.discriminant {
            return false;
        }

        unsafe {
            match self.discriminant {
                AddrInUse => self.payload.AddrInUse == other.payload.AddrInUse,
                AddrNotAvailable => self.payload.AddrNotAvailable == other.payload.AddrNotAvailable,
                AlreadyExists => self.payload.AlreadyExists == other.payload.AlreadyExists,
                ArgumentListTooLong => {
                    self.payload.ArgumentListTooLong == other.payload.ArgumentListTooLong
                }
                BrokenPipe => self.payload.BrokenPipe == other.payload.BrokenPipe,
                ConnectionAborted => {
                    self.payload.ConnectionAborted == other.payload.ConnectionAborted
                }
                ConnectionRefused => {
                    self.payload.ConnectionRefused == other.payload.ConnectionRefused
                }
                ConnectionReset => self.payload.ConnectionReset == other.payload.ConnectionReset,
                CrossesDevices => self.payload.CrossesDevices == other.payload.CrossesDevices,
                Deadlock => self.payload.Deadlock == other.payload.Deadlock,
                DirectoryNotEmpty => {
                    self.payload.DirectoryNotEmpty == other.payload.DirectoryNotEmpty
                }
                ExecutableFileBusy => {
                    self.payload.ExecutableFileBusy == other.payload.ExecutableFileBusy
                }
                FileTooLarge => self.payload.FileTooLarge == other.payload.FileTooLarge,
                FilesystemLoop => self.payload.FilesystemLoop == other.payload.FilesystemLoop,
                FilesystemQuotaExceeded => {
                    self.payload.FilesystemQuotaExceeded == other.payload.FilesystemQuotaExceeded
                }
                HostUnreachable => self.payload.HostUnreachable == other.payload.HostUnreachable,
                Interrupted => self.payload.Interrupted == other.payload.Interrupted,
                InvalidData => self.payload.InvalidData == other.payload.InvalidData,
                InvalidFilename => self.payload.InvalidFilename == other.payload.InvalidFilename,
                InvalidInput => self.payload.InvalidInput == other.payload.InvalidInput,
                IsADirectory => self.payload.IsADirectory == other.payload.IsADirectory,
                NetworkDown => self.payload.NetworkDown == other.payload.NetworkDown,
                NetworkUnreachable => {
                    self.payload.NetworkUnreachable == other.payload.NetworkUnreachable
                }
                NotADirectory => self.payload.NotADirectory == other.payload.NotADirectory,
                NotConnected => self.payload.NotConnected == other.payload.NotConnected,
                NotFound => self.payload.NotFound == other.payload.NotFound,
                NotSeekable => self.payload.NotSeekable == other.payload.NotSeekable,
                Other => self.payload.Other == other.payload.Other,
                OutOfMemory => self.payload.OutOfMemory == other.payload.OutOfMemory,
                PermissionDenied => self.payload.PermissionDenied == other.payload.PermissionDenied,
                ReadOnlyFilesystem => {
                    self.payload.ReadOnlyFilesystem == other.payload.ReadOnlyFilesystem
                }
                ResourceBusy => self.payload.ResourceBusy == other.payload.ResourceBusy,
                StaleNetworkFileHandle => {
                    self.payload.StaleNetworkFileHandle == other.payload.StaleNetworkFileHandle
                }
                StorageFull => self.payload.StorageFull == other.payload.StorageFull,
                TimedOut => self.payload.TimedOut == other.payload.TimedOut,
                TooManyLinks => self.payload.TooManyLinks == other.payload.TooManyLinks,
                UnexpectedEof => self.payload.UnexpectedEof == other.payload.UnexpectedEof,
                Unsupported => self.payload.Unsupported == other.payload.Unsupported,
                WouldBlock => self.payload.WouldBlock == other.payload.WouldBlock,
                WriteZero => self.payload.WriteZero == other.payload.WriteZero,
            }
        }
    }
}

impl Ord for IOError {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.partial_cmp(other).unwrap()
    }
}

impl PartialOrd for IOError {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        use discriminant_IOError::*;

        use std::cmp::Ordering::*;

        match self.discriminant.cmp(&other.discriminant) {
            Less => Option::Some(Less),
            Greater => Option::Some(Greater),
            Equal => unsafe {
                match self.discriminant {
                    AddrInUse => self.payload.AddrInUse.partial_cmp(&other.payload.AddrInUse),
                    AddrNotAvailable => self
                        .payload
                        .AddrNotAvailable
                        .partial_cmp(&other.payload.AddrNotAvailable),
                    AlreadyExists => self
                        .payload
                        .AlreadyExists
                        .partial_cmp(&other.payload.AlreadyExists),
                    ArgumentListTooLong => self
                        .payload
                        .ArgumentListTooLong
                        .partial_cmp(&other.payload.ArgumentListTooLong),
                    BrokenPipe => self
                        .payload
                        .BrokenPipe
                        .partial_cmp(&other.payload.BrokenPipe),
                    ConnectionAborted => self
                        .payload
                        .ConnectionAborted
                        .partial_cmp(&other.payload.ConnectionAborted),
                    ConnectionRefused => self
                        .payload
                        .ConnectionRefused
                        .partial_cmp(&other.payload.ConnectionRefused),
                    ConnectionReset => self
                        .payload
                        .ConnectionReset
                        .partial_cmp(&other.payload.ConnectionReset),
                    CrossesDevices => self
                        .payload
                        .CrossesDevices
                        .partial_cmp(&other.payload.CrossesDevices),
                    Deadlock => self.payload.Deadlock.partial_cmp(&other.payload.Deadlock),
                    DirectoryNotEmpty => self
                        .payload
                        .DirectoryNotEmpty
                        .partial_cmp(&other.payload.DirectoryNotEmpty),
                    ExecutableFileBusy => self
                        .payload
                        .ExecutableFileBusy
                        .partial_cmp(&other.payload.ExecutableFileBusy),
                    FileTooLarge => self
                        .payload
                        .FileTooLarge
                        .partial_cmp(&other.payload.FileTooLarge),
                    FilesystemLoop => self
                        .payload
                        .FilesystemLoop
                        .partial_cmp(&other.payload.FilesystemLoop),
                    FilesystemQuotaExceeded => self
                        .payload
                        .FilesystemQuotaExceeded
                        .partial_cmp(&other.payload.FilesystemQuotaExceeded),
                    HostUnreachable => self
                        .payload
                        .HostUnreachable
                        .partial_cmp(&other.payload.HostUnreachable),
                    Interrupted => self
                        .payload
                        .Interrupted
                        .partial_cmp(&other.payload.Interrupted),
                    InvalidData => self
                        .payload
                        .InvalidData
                        .partial_cmp(&other.payload.InvalidData),
                    InvalidFilename => self
                        .payload
                        .InvalidFilename
                        .partial_cmp(&other.payload.InvalidFilename),
                    InvalidInput => self
                        .payload
                        .InvalidInput
                        .partial_cmp(&other.payload.InvalidInput),
                    IsADirectory => self
                        .payload
                        .IsADirectory
                        .partial_cmp(&other.payload.IsADirectory),
                    NetworkDown => self
                        .payload
                        .NetworkDown
                        .partial_cmp(&other.payload.NetworkDown),
                    NetworkUnreachable => self
                        .payload
                        .NetworkUnreachable
                        .partial_cmp(&other.payload.NetworkUnreachable),
                    NotADirectory => self
                        .payload
                        .NotADirectory
                        .partial_cmp(&other.payload.NotADirectory),
                    NotConnected => self
                        .payload
                        .NotConnected
                        .partial_cmp(&other.payload.NotConnected),
                    NotFound => self.payload.NotFound.partial_cmp(&other.payload.NotFound),
                    NotSeekable => self
                        .payload
                        .NotSeekable
                        .partial_cmp(&other.payload.NotSeekable),
                    Other => self.payload.Other.partial_cmp(&other.payload.Other),
                    OutOfMemory => self
                        .payload
                        .OutOfMemory
                        .partial_cmp(&other.payload.OutOfMemory),
                    PermissionDenied => self
                        .payload
                        .PermissionDenied
                        .partial_cmp(&other.payload.PermissionDenied),
                    ReadOnlyFilesystem => self
                        .payload
                        .ReadOnlyFilesystem
                        .partial_cmp(&other.payload.ReadOnlyFilesystem),
                    ResourceBusy => self
                        .payload
                        .ResourceBusy
                        .partial_cmp(&other.payload.ResourceBusy),
                    StaleNetworkFileHandle => self
                        .payload
                        .StaleNetworkFileHandle
                        .partial_cmp(&other.payload.StaleNetworkFileHandle),
                    StorageFull => self
                        .payload
                        .StorageFull
                        .partial_cmp(&other.payload.StorageFull),
                    TimedOut => self.payload.TimedOut.partial_cmp(&other.payload.TimedOut),
                    TooManyLinks => self
                        .payload
                        .TooManyLinks
                        .partial_cmp(&other.payload.TooManyLinks),
                    UnexpectedEof => self
                        .payload
                        .UnexpectedEof
                        .partial_cmp(&other.payload.UnexpectedEof),
                    Unsupported => self
                        .payload
                        .Unsupported
                        .partial_cmp(&other.payload.Unsupported),
                    WouldBlock => self
                        .payload
                        .WouldBlock
                        .partial_cmp(&other.payload.WouldBlock),
                    WriteZero => self.payload.WriteZero.partial_cmp(&other.payload.WriteZero),
                }
            },
        }
    }
}

impl core::hash::Hash for IOError {
    fn hash<H: core::hash::Hasher>(&self, state: &mut H) {
        use discriminant_IOError::*;

        unsafe {
            match self.discriminant {
                AddrInUse => self.payload.AddrInUse.hash(state),
                AddrNotAvailable => self.payload.AddrNotAvailable.hash(state),
                AlreadyExists => self.payload.AlreadyExists.hash(state),
                ArgumentListTooLong => self.payload.ArgumentListTooLong.hash(state),
                BrokenPipe => self.payload.BrokenPipe.hash(state),
                ConnectionAborted => self.payload.ConnectionAborted.hash(state),
                ConnectionRefused => self.payload.ConnectionRefused.hash(state),
                ConnectionReset => self.payload.ConnectionReset.hash(state),
                CrossesDevices => self.payload.CrossesDevices.hash(state),
                Deadlock => self.payload.Deadlock.hash(state),
                DirectoryNotEmpty => self.payload.DirectoryNotEmpty.hash(state),
                ExecutableFileBusy => self.payload.ExecutableFileBusy.hash(state),
                FileTooLarge => self.payload.FileTooLarge.hash(state),
                FilesystemLoop => self.payload.FilesystemLoop.hash(state),
                FilesystemQuotaExceeded => self.payload.FilesystemQuotaExceeded.hash(state),
                HostUnreachable => self.payload.HostUnreachable.hash(state),
                Interrupted => self.payload.Interrupted.hash(state),
                InvalidData => self.payload.InvalidData.hash(state),
                InvalidFilename => self.payload.InvalidFilename.hash(state),
                InvalidInput => self.payload.InvalidInput.hash(state),
                IsADirectory => self.payload.IsADirectory.hash(state),
                NetworkDown => self.payload.NetworkDown.hash(state),
                NetworkUnreachable => self.payload.NetworkUnreachable.hash(state),
                NotADirectory => self.payload.NotADirectory.hash(state),
                NotConnected => self.payload.NotConnected.hash(state),
                NotFound => self.payload.NotFound.hash(state),
                NotSeekable => self.payload.NotSeekable.hash(state),
                Other => self.payload.Other.hash(state),
                OutOfMemory => self.payload.OutOfMemory.hash(state),
                PermissionDenied => self.payload.PermissionDenied.hash(state),
                ReadOnlyFilesystem => self.payload.ReadOnlyFilesystem.hash(state),
                ResourceBusy => self.payload.ResourceBusy.hash(state),
                StaleNetworkFileHandle => self.payload.StaleNetworkFileHandle.hash(state),
                StorageFull => self.payload.StorageFull.hash(state),
                TimedOut => self.payload.TimedOut.hash(state),
                TooManyLinks => self.payload.TooManyLinks.hash(state),
                UnexpectedEof => self.payload.UnexpectedEof.hash(state),
                Unsupported => self.payload.Unsupported.hash(state),
                WouldBlock => self.payload.WouldBlock.hash(state),
                WriteZero => self.payload.WriteZero.hash(state),
            }
        }
    }
}

impl IOError {
    pub fn is_AddrInUse(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::AddrInUse)
    }

    pub fn is_AddrNotAvailable(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::AddrNotAvailable)
    }

    pub fn is_AlreadyExists(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::AlreadyExists)
    }

    pub fn is_ArgumentListTooLong(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::ArgumentListTooLong)
    }

    pub fn is_BrokenPipe(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::BrokenPipe)
    }

    pub fn is_ConnectionAborted(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::ConnectionAborted)
    }

    pub fn is_ConnectionRefused(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::ConnectionRefused)
    }

    pub fn is_ConnectionReset(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::ConnectionReset)
    }

    pub fn is_CrossesDevices(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::CrossesDevices)
    }

    pub fn is_Deadlock(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::Deadlock)
    }

    pub fn is_DirectoryNotEmpty(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::DirectoryNotEmpty)
    }

    pub fn is_ExecutableFileBusy(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::ExecutableFileBusy)
    }

    pub fn is_FileTooLarge(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::FileTooLarge)
    }

    pub fn is_FilesystemLoop(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::FilesystemLoop)
    }

    pub fn is_FilesystemQuotaExceeded(&self) -> bool {
        matches!(
            self.discriminant,
            discriminant_IOError::FilesystemQuotaExceeded
        )
    }

    pub fn is_HostUnreachable(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::HostUnreachable)
    }

    pub fn is_Interrupted(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::Interrupted)
    }

    pub fn is_InvalidData(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::InvalidData)
    }

    pub fn is_InvalidFilename(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::InvalidFilename)
    }

    pub fn is_InvalidInput(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::InvalidInput)
    }

    pub fn is_IsADirectory(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::IsADirectory)
    }

    pub fn is_NetworkDown(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::NetworkDown)
    }

    pub fn is_NetworkUnreachable(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::NetworkUnreachable)
    }

    pub fn is_NotADirectory(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::NotADirectory)
    }

    pub fn is_NotConnected(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::NotConnected)
    }

    pub fn is_NotFound(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::NotFound)
    }

    pub fn is_NotSeekable(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::NotSeekable)
    }

    pub fn is_Other(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::Other)
    }

    pub fn is_OutOfMemory(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::OutOfMemory)
    }

    pub fn is_PermissionDenied(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::PermissionDenied)
    }

    pub fn is_ReadOnlyFilesystem(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::ReadOnlyFilesystem)
    }

    pub fn is_ResourceBusy(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::ResourceBusy)
    }

    pub fn is_StaleNetworkFileHandle(&self) -> bool {
        matches!(
            self.discriminant,
            discriminant_IOError::StaleNetworkFileHandle
        )
    }

    pub fn is_StorageFull(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::StorageFull)
    }

    pub fn is_TimedOut(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::TimedOut)
    }

    pub fn is_TooManyLinks(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::TooManyLinks)
    }

    pub fn is_UnexpectedEof(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::UnexpectedEof)
    }

    pub fn is_Unsupported(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::Unsupported)
    }

    pub fn is_WouldBlock(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::WouldBlock)
    }

    pub fn is_WriteZero(&self) -> bool {
        matches!(self.discriminant, discriminant_IOError::WriteZero)
    }
}

impl IOError {
    pub fn AddrInUse() -> Self {
        Self {
            discriminant: discriminant_IOError::AddrInUse,
            payload: union_IOError { AddrInUse: () },
        }
    }

    pub fn AddrNotAvailable() -> Self {
        Self {
            discriminant: discriminant_IOError::AddrNotAvailable,
            payload: union_IOError {
                AddrNotAvailable: (),
            },
        }
    }

    pub fn AlreadyExists() -> Self {
        Self {
            discriminant: discriminant_IOError::AlreadyExists,
            payload: union_IOError { AlreadyExists: () },
        }
    }

    pub fn ArgumentListTooLong() -> Self {
        Self {
            discriminant: discriminant_IOError::ArgumentListTooLong,
            payload: union_IOError {
                ArgumentListTooLong: (),
            },
        }
    }

    pub fn BrokenPipe() -> Self {
        Self {
            discriminant: discriminant_IOError::BrokenPipe,
            payload: union_IOError { BrokenPipe: () },
        }
    }

    pub fn ConnectionAborted() -> Self {
        Self {
            discriminant: discriminant_IOError::ConnectionAborted,
            payload: union_IOError {
                ConnectionAborted: (),
            },
        }
    }

    pub fn ConnectionRefused() -> Self {
        Self {
            discriminant: discriminant_IOError::ConnectionRefused,
            payload: union_IOError {
                ConnectionRefused: (),
            },
        }
    }

    pub fn ConnectionReset() -> Self {
        Self {
            discriminant: discriminant_IOError::ConnectionReset,
            payload: union_IOError {
                ConnectionReset: (),
            },
        }
    }

    pub fn CrossesDevices() -> Self {
        Self {
            discriminant: discriminant_IOError::CrossesDevices,
            payload: union_IOError { CrossesDevices: () },
        }
    }

    pub fn Deadlock() -> Self {
        Self {
            discriminant: discriminant_IOError::Deadlock,
            payload: union_IOError { Deadlock: () },
        }
    }

    pub fn DirectoryNotEmpty() -> Self {
        Self {
            discriminant: discriminant_IOError::DirectoryNotEmpty,
            payload: union_IOError {
                DirectoryNotEmpty: (),
            },
        }
    }

    pub fn ExecutableFileBusy() -> Self {
        Self {
            discriminant: discriminant_IOError::ExecutableFileBusy,
            payload: union_IOError {
                ExecutableFileBusy: (),
            },
        }
    }

    pub fn FileTooLarge() -> Self {
        Self {
            discriminant: discriminant_IOError::FileTooLarge,
            payload: union_IOError { FileTooLarge: () },
        }
    }

    pub fn FilesystemLoop() -> Self {
        Self {
            discriminant: discriminant_IOError::FilesystemLoop,
            payload: union_IOError { FilesystemLoop: () },
        }
    }

    pub fn FilesystemQuotaExceeded() -> Self {
        Self {
            discriminant: discriminant_IOError::FilesystemQuotaExceeded,
            payload: union_IOError {
                FilesystemQuotaExceeded: (),
            },
        }
    }

    pub fn HostUnreachable() -> Self {
        Self {
            discriminant: discriminant_IOError::HostUnreachable,
            payload: union_IOError {
                HostUnreachable: (),
            },
        }
    }

    pub fn Interrupted() -> Self {
        Self {
            discriminant: discriminant_IOError::Interrupted,
            payload: union_IOError { Interrupted: () },
        }
    }

    pub fn InvalidData() -> Self {
        Self {
            discriminant: discriminant_IOError::InvalidData,
            payload: union_IOError { InvalidData: () },
        }
    }

    pub fn InvalidFilename() -> Self {
        Self {
            discriminant: discriminant_IOError::InvalidFilename,
            payload: union_IOError {
                InvalidFilename: (),
            },
        }
    }

    pub fn InvalidInput() -> Self {
        Self {
            discriminant: discriminant_IOError::InvalidInput,
            payload: union_IOError { InvalidInput: () },
        }
    }

    pub fn IsADirectory() -> Self {
        Self {
            discriminant: discriminant_IOError::IsADirectory,
            payload: union_IOError { IsADirectory: () },
        }
    }

    pub fn NetworkDown() -> Self {
        Self {
            discriminant: discriminant_IOError::NetworkDown,
            payload: union_IOError { NetworkDown: () },
        }
    }

    pub fn NetworkUnreachable() -> Self {
        Self {
            discriminant: discriminant_IOError::NetworkUnreachable,
            payload: union_IOError {
                NetworkUnreachable: (),
            },
        }
    }

    pub fn NotADirectory() -> Self {
        Self {
            discriminant: discriminant_IOError::NotADirectory,
            payload: union_IOError { NotADirectory: () },
        }
    }

    pub fn NotConnected() -> Self {
        Self {
            discriminant: discriminant_IOError::NotConnected,
            payload: union_IOError { NotConnected: () },
        }
    }

    pub fn NotFound() -> Self {
        Self {
            discriminant: discriminant_IOError::NotFound,
            payload: union_IOError { NotFound: () },
        }
    }

    pub fn NotSeekable() -> Self {
        Self {
            discriminant: discriminant_IOError::NotSeekable,
            payload: union_IOError { NotSeekable: () },
        }
    }

    pub fn Other() -> Self {
        Self {
            discriminant: discriminant_IOError::Other,
            payload: union_IOError { Other: () },
        }
    }

    pub fn OutOfMemory() -> Self {
        Self {
            discriminant: discriminant_IOError::OutOfMemory,
            payload: union_IOError { OutOfMemory: () },
        }
    }

    pub fn PermissionDenied() -> Self {
        Self {
            discriminant: discriminant_IOError::PermissionDenied,
            payload: union_IOError {
                PermissionDenied: (),
            },
        }
    }

    pub fn ReadOnlyFilesystem() -> Self {
        Self {
            discriminant: discriminant_IOError::ReadOnlyFilesystem,
            payload: union_IOError {
                ReadOnlyFilesystem: (),
            },
        }
    }

    pub fn ResourceBusy() -> Self {
        Self {
            discriminant: discriminant_IOError::ResourceBusy,
            payload: union_IOError { ResourceBusy: () },
        }
    }

    pub fn StaleNetworkFileHandle() -> Self {
        Self {
            discriminant: discriminant_IOError::StaleNetworkFileHandle,
            payload: union_IOError {
                StaleNetworkFileHandle: (),
            },
        }
    }

    pub fn StorageFull() -> Self {
        Self {
            discriminant: discriminant_IOError::StorageFull,
            payload: union_IOError { StorageFull: () },
        }
    }

    pub fn TimedOut() -> Self {
        Self {
            discriminant: discriminant_IOError::TimedOut,
            payload: union_IOError { TimedOut: () },
        }
    }

    pub fn TooManyLinks() -> Self {
        Self {
            discriminant: discriminant_IOError::TooManyLinks,
            payload: union_IOError { TooManyLinks: () },
        }
    }

    pub fn UnexpectedEof() -> Self {
        Self {
            discriminant: discriminant_IOError::UnexpectedEof,
            payload: union_IOError { UnexpectedEof: () },
        }
    }

    pub fn Unsupported() -> Self {
        Self {
            discriminant: discriminant_IOError::Unsupported,
            payload: union_IOError { Unsupported: () },
        }
    }

    pub fn WouldBlock() -> Self {
        Self {
            discriminant: discriminant_IOError::WouldBlock,
            payload: union_IOError { WouldBlock: () },
        }
    }

    pub fn WriteZero() -> Self {
        Self {
            discriminant: discriminant_IOError::WriteZero,
            payload: union_IOError { WriteZero: () },
        }
    }
}
