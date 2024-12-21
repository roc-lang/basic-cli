use roc_std::{roc_refcounted_noop_impl, RocList, RocRefcounted};
use std::ffi::OsString;

#[derive(Clone, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct ArgToAndFromHost {
    pub unix: RocList<u8>,
    pub windows: RocList<u16>,
    pub tag: ArgTag,
}

impl From<&[u8]> for ArgToAndFromHost {
    #[cfg(target_os = "macos")]
    fn from(bytes: &[u8]) -> Self {
        ArgToAndFromHost {
            unix: RocList::from_slice(bytes),
            windows: RocList::empty(),
            tag: ArgTag::Unix,
        }
    }

    #[cfg(target_os = "linux")]
    fn from(bytes: &[u8]) -> Self {
        ArgToAndFromHost {
            unix: RocList::from_slice(bytes),
            windows: RocList::empty(),
            tag: ArgTag::Unix,
        }
    }

    #[cfg(target_os = "windows")]
    fn from(bytes: &[u8]) -> Self {
        todo!()
        // use something like
        // https://docs.rs/widestring/latest/widestring/
        // to support Windows
    }
}

impl From<OsString> for ArgToAndFromHost {
    #[cfg(target_os = "macos")]
    fn from(os_str: OsString) -> Self {
        ArgToAndFromHost {
            unix: RocList::from_slice(os_str.as_encoded_bytes()),
            windows: RocList::empty(),
            tag: ArgTag::Unix,
        }
    }

    #[cfg(target_os = "linux")]
    fn from(os_str: OsString) -> Self {
        ArgToAndFromHost {
            unix: RocList::from_slice(os_str.as_encoded_bytes()),
            windows: RocList::empty(),
            tag: ArgTag::Unix,
        }
    }

    #[cfg(target_os = "windows")]
    fn from(os_str: OsString) -> Self {
        todo!()
        // use something like
        // https://docs.rs/widestring/latest/widestring/
        // to support Windows
    }
}

#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(u8)]
pub enum ArgTag {
    Unix = 0,
    Windows = 1,
}

impl core::fmt::Debug for ArgTag {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::Unix => f.write_str("ArgTag::Unix"),
            Self::Windows => f.write_str("ArgTag::Windows"),
        }
    }
}

roc_refcounted_noop_impl!(ArgTag);

impl roc_std::RocRefcounted for ArgToAndFromHost {
    fn inc(&mut self) {
        self.unix.inc();
        self.windows.inc();
    }
    fn dec(&mut self) {
        self.unix.dec();
        self.windows.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}
