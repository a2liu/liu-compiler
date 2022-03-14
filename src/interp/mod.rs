use crate::util::*;
use crate::*;
use core::fmt::Write;
use core::mem;
use core::num::NonZeroU32;

mod memory;
mod types;

pub use memory::*;
pub use types::*;

pub struct Interpreter<'a> {
    memory: Memory,
    out: &'a mut dyn Write,
}

impl<'a> Interpreter<'a> {
    pub fn new(out: &'a mut dyn Write) -> Self {
        return Self {
            memory: Memory::new(),
            out,
        };
    }

    pub fn run(&mut self) {}
}
