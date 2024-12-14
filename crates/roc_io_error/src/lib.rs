//! This crate provides common functionality for Roc to interface with `std::io::Error`
use roc_std::{roc_refcounted_noop_impl, RocRefcounted, RocStr};

#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(u8)]
pub enum IOErrTag {
    AlreadyExists = 0,
    BrokenPipe = 1,
    EndOfFile = 2,
    Interrupted = 3,
    NotFound = 4,
    Other = 5,
    OutOfMemory = 6,
    PermissionDenied = 7,
    Unsupported = 8,
}

impl core::fmt::Debug for IOErrTag {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::AlreadyExists => f.write_str("IOErrTag::AlreadyExists"),
            Self::BrokenPipe => f.write_str("IOErrTag::BrokenPipe"),
            Self::EndOfFile => f.write_str("IOErrTag::EndOfFile"),
            Self::Interrupted => f.write_str("IOErrTag::Interrupted"),
            Self::NotFound => f.write_str("IOErrTag::NotFound"),
            Self::Other => f.write_str("IOErrTag::Other"),
            Self::OutOfMemory => f.write_str("IOErrTag::OutOfMemory"),
            Self::PermissionDenied => f.write_str("IOErrTag::PermissionDenied"),
            Self::Unsupported => f.write_str("IOErrTag::Unsupported"),
        }
    }
}

roc_refcounted_noop_impl!(IOErrTag);

#[derive(Clone, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct IOErr {
    pub msg: roc_std::RocStr,
    pub tag: IOErrTag,
}

impl roc_std::RocRefcounted for IOErr {
    fn inc(&mut self) {
        self.msg.inc();
    }
    fn dec(&mut self) {
        self.msg.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

impl From<std::io::Error> for IOErr {
    fn from(e: std::io::Error) -> Self {
        let other = || -> IOErr {
            IOErr {
                tag: IOErrTag::Other,
                msg: format!("{}", e).as_str().into(),
            }
        };

        let with_empty_msg = |tag: IOErrTag| -> IOErr {
            IOErr {
                tag,
                msg: RocStr::empty(),
            }
        };

        match e.kind() {
            std::io::ErrorKind::NotFound => with_empty_msg(IOErrTag::NotFound),
            std::io::ErrorKind::PermissionDenied => with_empty_msg(IOErrTag::PermissionDenied),
            std::io::ErrorKind::BrokenPipe => with_empty_msg(IOErrTag::BrokenPipe),
            std::io::ErrorKind::AlreadyExists => with_empty_msg(IOErrTag::AlreadyExists),
            std::io::ErrorKind::Interrupted => with_empty_msg(IOErrTag::Interrupted),
            std::io::ErrorKind::Unsupported => with_empty_msg(IOErrTag::Unsupported),
            std::io::ErrorKind::OutOfMemory => with_empty_msg(IOErrTag::OutOfMemory),
            _ => other(),
        }
    }
}
