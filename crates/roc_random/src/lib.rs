//! This crate provides random number generation for Roc via getrandom.

use roc_io_error::IOErr;
use roc_std_new::RocOps;

/// Generate a random u64 seed.
pub fn random_u64(roc_ops: &RocOps) -> Result<u64, IOErr> {
    let mut bytes = [0u8; 8];
    getrandom::getrandom(&mut bytes)
        .map_err(|e| {
            let io_err = std::io::Error::new(std::io::ErrorKind::Other, e.to_string());
            IOErr::from_io_error(&io_err, roc_ops)
        })?;
    Ok(u64::from_ne_bytes(bytes))
}

/// Generate a random u32 seed.
pub fn random_u32(roc_ops: &RocOps) -> Result<u32, IOErr> {
    let mut bytes = [0u8; 4];
    getrandom::getrandom(&mut bytes)
        .map_err(|e| {
            let io_err = std::io::Error::new(std::io::ErrorKind::Other, e.to_string());
            IOErr::from_io_error(&io_err, roc_ops)
        })?;
    Ok(u32::from_ne_bytes(bytes))
}
