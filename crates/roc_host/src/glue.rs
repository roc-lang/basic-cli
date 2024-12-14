use roc_std::{roc_refcounted_noop_impl, RocRefcounted, RocStr};

#[derive(Debug)]
#[repr(C)]
pub struct ReturnArchOS {
    pub arch: RocStr,
    pub os: RocStr,
}

roc_refcounted_noop_impl!(ReturnArchOS);

#[repr(C)]
pub struct Variable {
    pub name: RocStr,
    pub value: RocStr,
}

impl roc_std::RocRefcounted for Variable {
    fn inc(&mut self) {
        self.name.inc();
        self.value.inc();
    }
    fn dec(&mut self) {
        self.name.dec();
        self.value.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}
