use roc_std::{RocList, RocResult};
use roc_io_error::IOErr;


pub fn random_u64() -> RocResult<u64, IOErr> {
    getrandom::u64()
        .map_err(|e| std::io::Error::from(e))
        .map_err(|e| IOErr::from(e))
        .into()
}

pub fn random_u32() -> RocResult<u32, IOErr> {
    getrandom::u32()
        .map_err(|e| std::io::Error::from(e))
        .map_err(|e| IOErr::from(e))
        .into()
}

pub fn random_bytes(count: u64) -> RocResult<RocList<u8>, IOErr> {
    let mut buf = RocList::from_iter((0..count).map(|_| 0u8));
    getrandom::fill(buf.as_mut_slice())
        .map(|_| buf)
        .map_err(|e| std::io::Error::from(e))
        .map_err(|e| IOErr::from(e))
        .into()
}
