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
    pub fn new(data: AllocTracker, out: &'a mut dyn Write) -> Self {
        return Self {
            memory: Memory::new(data),
            out,
        };
    }

    pub fn run(&mut self) -> Result<(), IError> {
        use Opcode::*;

        let opcode: Opcode = self.memory.read_op()?.into();

        loop {
            match opcode {
                StackAlloc {
                    len,
                    len_power,
                    register_out,
                } => {
                    let ptr = self.memory.alloc_stack_var(len, len_power)?;

                    if let Some(id) = register_out.id() {
                        self.memory.write_register(id, ptr.into())?;
                    }

                    self.memory.advance_pc();
                }

                _ => {
                    break;
                }
            }
        }

        return Ok(());
    }
}
