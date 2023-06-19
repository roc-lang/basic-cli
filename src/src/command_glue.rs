
#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash, )]
#[repr(C)]
pub struct Output {
    pub stderr: roc_std::RocList<u8>,
    pub stdout: roc_std::RocList<u8>,
    pub status: i32,
}

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash, )]
#[repr(C)]
pub struct Command {
    pub args: roc_std::RocList<roc_std::RocStr>,
    pub envs: roc_std::RocList<roc_std::RocStr>,
    pub program: roc_std::RocStr,
}