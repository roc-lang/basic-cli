use roc_std::RocResult;
use roc_io_error::IOErr;


pub fn seed() -> RocResult<u64, IOErr> {
    getrandom::u64()
        .map_err(|e| std::io::Error::from(e))
        .map_err(|e| IOErr::from(e))
        .into()
}
