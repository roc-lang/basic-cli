//! This crate provides common functionality for Roc to interface with `std::io::Error`
//!
//! Matches the Roc type:
//! ```roc
//! IOErr := [
//!     AlreadyExists,
//!     BrokenPipe,
//!     Interrupted,
//!     NotFound,
//!     Other(Str),
//!     OutOfMemory,
//!     PermissionDenied,
//!     Unsupported,
//! ]
//! ```

use core::mem::MaybeUninit;
use roc_std_new::{roc_refcounted_noop_impl, RocOps, RocRefcounted, RocStr};

/// Tag discriminant for IOErr, sorted alphabetically.
#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(u8)]
pub enum IOErrTag {
    AlreadyExists = 0,
    BrokenPipe = 1,
    Interrupted = 2,
    NotFound = 3,
    Other = 4,
    OutOfMemory = 5,
    PermissionDenied = 6,
    Unsupported = 7,
}

impl core::fmt::Debug for IOErrTag {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::AlreadyExists => f.write_str("IOErrTag::AlreadyExists"),
            Self::BrokenPipe => f.write_str("IOErrTag::BrokenPipe"),
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

/// IOErr representation matching the Roc tag union.
/// Layout: payload area (sized for largest variant) followed by tag byte.
#[repr(C)]
pub struct IOErr {
    /// Payload area - only valid for the Other variant (tag == 4)
    payload: MaybeUninit<RocStr>,
    /// Tag discriminant
    pub tag: IOErrTag,
}

impl IOErr {
    /// Create an IOErr for simple tags (no payload)
    pub fn new_simple(tag: IOErrTag) -> Self {
        debug_assert!(tag != IOErrTag::Other, "Use new_other for Other variant");
        Self {
            payload: MaybeUninit::zeroed(),
            tag,
        }
    }

    /// Create an IOErr for the Other variant with a message
    pub fn new_other(msg: &str, roc_ops: &RocOps) -> Self {
        Self {
            payload: MaybeUninit::new(RocStr::from_str(msg, roc_ops)),
            tag: IOErrTag::Other,
        }
    }

    /// Convenience constructors for common errors
    pub fn not_found() -> Self {
        Self::new_simple(IOErrTag::NotFound)
    }

    pub fn permission_denied() -> Self {
        Self::new_simple(IOErrTag::PermissionDenied)
    }

    pub fn already_exists() -> Self {
        Self::new_simple(IOErrTag::AlreadyExists)
    }

    /// Convert from std::io::Error
    pub fn from_io_error(e: &std::io::Error, roc_ops: &RocOps) -> Self {
        match e.kind() {
            std::io::ErrorKind::NotFound => Self::not_found(),
            std::io::ErrorKind::PermissionDenied => Self::permission_denied(),
            std::io::ErrorKind::AlreadyExists => Self::already_exists(),
            std::io::ErrorKind::BrokenPipe => Self::new_simple(IOErrTag::BrokenPipe),
            std::io::ErrorKind::Interrupted => Self::new_simple(IOErrTag::Interrupted),
            std::io::ErrorKind::Unsupported => Self::new_simple(IOErrTag::Unsupported),
            std::io::ErrorKind::OutOfMemory => Self::new_simple(IOErrTag::OutOfMemory),
            _ => Self::new_other(&format!("{}", e), roc_ops),
        }
    }
}

impl Clone for IOErr {
    fn clone(&self) -> Self {
        if self.tag == IOErrTag::Other {
            Self {
                payload: MaybeUninit::new(unsafe { self.payload.assume_init_ref().clone() }),
                tag: self.tag,
            }
        } else {
            Self {
                payload: MaybeUninit::zeroed(),
                tag: self.tag,
            }
        }
    }
}

impl core::fmt::Debug for IOErr {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        if self.tag == IOErrTag::Other {
            write!(f, "IOErr::Other({:?})", unsafe {
                self.payload.assume_init_ref()
            })
        } else {
            write!(f, "IOErr::{:?}", self.tag)
        }
    }
}

impl RocRefcounted for IOErr {
    fn inc(&mut self) {
        if self.tag == IOErrTag::Other {
            unsafe { self.payload.assume_init_mut().inc() };
        }
    }
    fn dec(&mut self) {
        if self.tag == IOErrTag::Other {
            unsafe { self.payload.assume_init_mut().dec() };
        }
    }
    fn is_refcounted() -> bool {
        true
    }
}
