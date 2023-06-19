
#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash, )]
#[repr(C)]
pub struct Output {
    pub stderr: roc_std::RocList<u8>,
    pub stdout: roc_std::RocList<u8>,
}

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash, )]
#[repr(C)]
pub struct Command {
    pub args: roc_std::RocList<roc_std::RocStr>,
    pub envs: roc_std::RocList<roc_std::RocStr>,
    pub program: roc_std::RocStr,
}

#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash, )]
#[repr(u8)]
pub enum discriminant_CommandErr {
    ExitStatus = 0,
    IOError = 1,
}

impl core::fmt::Debug for discriminant_CommandErr {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::ExitStatus => f.write_str("discriminant_CommandErr::ExitStatus"),
            Self::IOError => f.write_str("discriminant_CommandErr::IOError"),
        }
    }
}

#[repr(C, align(8))]
pub union union_CommandErr {
    ExitStatus: i32,
    IOError: core::mem::ManuallyDrop<roc_std::RocStr>,
}

const _SIZE_CHECK_union_CommandErr: () = assert!(core::mem::size_of::<union_CommandErr>() == 24);
const _ALIGN_CHECK_union_CommandErr: () = assert!(core::mem::align_of::<union_CommandErr>() == 8);

const _SIZE_CHECK_CommandErr: () = assert!(core::mem::size_of::<CommandErr>() == 32);
const _ALIGN_CHECK_CommandErr: () = assert!(core::mem::align_of::<CommandErr>() == 8);

impl CommandErr {
    /// Returns which variant this tag union holds. Note that this never includes a payload!
    pub fn discriminant(&self) -> discriminant_CommandErr {
        unsafe {
            let bytes = core::mem::transmute::<&Self, &[u8; core::mem::size_of::<Self>()]>(self);

            core::mem::transmute::<u8, discriminant_CommandErr>(*bytes.as_ptr().add(24))
        }
    }

    /// Internal helper
    fn set_discriminant(&mut self, discriminant: discriminant_CommandErr) {
        let discriminant_ptr: *mut discriminant_CommandErr = (self as *mut CommandErr).cast();

        unsafe {
            *(discriminant_ptr.add(24)) = discriminant;
        }
    }
}

#[repr(C)]
pub struct CommandErr {
    payload: union_CommandErr,
    discriminant: discriminant_CommandErr,
}

impl Clone for CommandErr {
    fn clone(&self) -> Self {
        use discriminant_CommandErr::*;

        let payload = unsafe {
            match self.discriminant {
                ExitStatus => union_CommandErr {
                    ExitStatus: self.payload.ExitStatus.clone(),
                },
                IOError => union_CommandErr {
                    IOError: self.payload.IOError.clone(),
                },
            }
        };

        Self {
            discriminant: self.discriminant,
            payload,
        }
    }
}

impl core::fmt::Debug for CommandErr {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        use discriminant_CommandErr::*;

        unsafe {
            match self.discriminant {
                ExitStatus => {
                    let field: &i32 = &self.payload.ExitStatus;
                    f.debug_tuple("CommandErr::ExitStatus").field(field).finish()
                },
                IOError => {
                    let field: &roc_std::RocStr = &self.payload.IOError;
                    f.debug_tuple("CommandErr::IOError").field(field).finish()
                },
            }
        }
    }
}

impl Eq for CommandErr {}

impl PartialEq for CommandErr {
    fn eq(&self, other: &Self) -> bool {
        use discriminant_CommandErr::*;

        if self.discriminant != other.discriminant {
            return false;
        }

        unsafe {
            match self.discriminant {
                ExitStatus => self.payload.ExitStatus == other.payload.ExitStatus,
                IOError => self.payload.IOError == other.payload.IOError,
            }
        }
    }
}

impl Ord for CommandErr {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.partial_cmp(other).unwrap()
    }
}

impl PartialOrd for CommandErr {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        use discriminant_CommandErr::*;

        use std::cmp::Ordering::*;

        match self.discriminant.cmp(&other.discriminant) {
            Less => Option::Some(Less),
            Greater => Option::Some(Greater),
            Equal => unsafe {
                match self.discriminant {
                    ExitStatus => self.payload.ExitStatus.partial_cmp(&other.payload.ExitStatus),
                    IOError => self.payload.IOError.partial_cmp(&other.payload.IOError),
                }
            },
        }
    }
}

impl core::hash::Hash for CommandErr {
    fn hash<H: core::hash::Hasher>(&self, state: &mut H) {
        use discriminant_CommandErr::*;

        unsafe {
            match self.discriminant {
                ExitStatus => self.payload.ExitStatus.hash(state),
                IOError => self.payload.IOError.hash(state),
            }
        }
    }
}

impl CommandErr {

    pub fn unwrap_ExitStatus(mut self) -> i32 {
        debug_assert_eq!(self.discriminant, discriminant_CommandErr::ExitStatus);
        unsafe { self.payload.ExitStatus }
    }

    pub fn is_ExitStatus(&self) -> bool {
        matches!(self.discriminant, discriminant_CommandErr::ExitStatus)
    }

    pub fn unwrap_IOError(mut self) -> roc_std::RocStr {
        debug_assert_eq!(self.discriminant, discriminant_CommandErr::IOError);
        unsafe { core::mem::ManuallyDrop::take(&mut self.payload.IOError) }
    }

    pub fn is_IOError(&self) -> bool {
        matches!(self.discriminant, discriminant_CommandErr::IOError)
    }
}



impl CommandErr {

    pub fn ExitStatus(payload: i32) -> Self {
        Self {
            discriminant: discriminant_CommandErr::ExitStatus,
            payload: union_CommandErr {
                ExitStatus: payload,
            }
        }
    }

    pub fn IOError(payload: roc_std::RocStr) -> Self {
        Self {
            discriminant: discriminant_CommandErr::IOError,
            payload: union_CommandErr {
                IOError: core::mem::ManuallyDrop::new(payload),
            }
        }
    }
}

impl Drop for CommandErr {
    fn drop(&mut self) {
        // Drop the payloads
        match self.discriminant() {
            discriminant_CommandErr::ExitStatus => {}
            discriminant_CommandErr::IOError => unsafe { core::mem::ManuallyDrop::drop(&mut self.payload.IOError) },
        }
    }
}
