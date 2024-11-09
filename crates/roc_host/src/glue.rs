use roc_std::roc_refcounted_noop_impl;
use roc_std::RocRefcounted;
use roc_std::RocStr;

#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(u8)]
pub enum InternalIOErrTag {
    BrokenPipe = 0,
    Interrupted = 1,
    InvalidInput = 2,
    Other = 3,
    OutOfMemory = 4,
    UnexpectedEof = 5,
    Unsupported = 6,
    WouldBlock = 7,
    WriteZero = 8,
}

impl core::fmt::Debug for InternalIOErrTag {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::BrokenPipe => f.write_str("InternalIOErr::BrokenPipe"),
            Self::Interrupted => f.write_str("InternalIOErr::Interrupted"),
            Self::InvalidInput => f.write_str("InternalIOErr::InvalidInput"),
            Self::Other => f.write_str("InternalIOErr::Other"),
            Self::OutOfMemory => f.write_str("InternalIOErr::OutOfMemory"),
            Self::UnexpectedEof => f.write_str("InternalIOErr::UnexpectedEof"),
            Self::Unsupported => f.write_str("InternalIOErr::Unsupported"),
            Self::WouldBlock => f.write_str("InternalIOErr::WouldBlock"),
            Self::WriteZero => f.write_str("InternalIOErr::WriteZero"),
        }
    }
}

roc_refcounted_noop_impl!(InternalIOErrTag);

#[derive(Clone, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct InternalIOErr {
    pub msg: roc_std::RocStr,
    pub tag: InternalIOErrTag,
}

impl roc_std::RocRefcounted for InternalIOErr {
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

impl From<std::io::Error> for InternalIOErr {
    fn from(e: std::io::Error) -> Self {
        match e.kind() {
            std::io::ErrorKind::BrokenPipe => InternalIOErr {
                tag: InternalIOErrTag::BrokenPipe,
                msg: RocStr::empty(),
            },
            std::io::ErrorKind::OutOfMemory => InternalIOErr {
                tag: InternalIOErrTag::OutOfMemory,
                msg: RocStr::empty(),
            },
            std::io::ErrorKind::WriteZero => InternalIOErr {
                tag: InternalIOErrTag::WriteZero,
                msg: RocStr::empty(),
            },
            std::io::ErrorKind::ConnectionAborted
            | std::io::ErrorKind::ConnectionReset
            | std::io::ErrorKind::NotConnected
            | std::io::ErrorKind::UnexpectedEof => InternalIOErr {
                tag: InternalIOErrTag::UnexpectedEof,
                msg: RocStr::empty(),
            },
            std::io::ErrorKind::Interrupted => InternalIOErr {
                tag: InternalIOErrTag::Interrupted,
                msg: RocStr::empty(),
            },
            std::io::ErrorKind::InvalidData | std::io::ErrorKind::InvalidInput => InternalIOErr {
                tag: InternalIOErrTag::InvalidInput,
                msg: RocStr::empty(),
            },
            std::io::ErrorKind::TimedOut => InternalIOErr {
                tag: InternalIOErrTag::WouldBlock,
                msg: RocStr::empty(),
            },
            std::io::ErrorKind::WouldBlock => InternalIOErr {
                tag: InternalIOErrTag::WouldBlock,
                msg: RocStr::empty(),
            },
            std::io::ErrorKind::AddrInUse | std::io::ErrorKind::AddrNotAvailable => InternalIOErr {
                tag: InternalIOErrTag::Unsupported,
                msg: RocStr::empty(),
            },
            _ => InternalIOErr {
                tag: InternalIOErrTag::Other,
                msg: format!("{}", e).as_str().into(),
            },
        }
    }
}
