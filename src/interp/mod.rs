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

        loop {
            let opcode: Opcode = self.memory.read_op()?.into();

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

                StackDealloc { count } => {
                    self.memory.drop_stack_vars(count as u32)?;

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

#[cfg(test)]
mod tests {
    use super::*;
    use Opcode::*;

    #[test]
    fn simple() {
        let mut data = AllocTracker::new();

        let mut ops: Pod<u32> = Pod::new();

        ops.push(
            StackAlloc {
                len: 1,
                len_power: 3,
                register_out: Out64Register::new(false, 2),
            }
            .into(),
        );

        ops.push(StackDealloc { count: 1 }.into());

        ops.push(
            Ecall {
                ecall_type: 0,
                register_64_input_1: 0,
                register_64_input_2: 0,
            }
            .into(),
        );

        data.alloc_exe(ops.len() as u32).copy_from_slice(&ops);

        let mut out = String::new();

        let mut interp = Interpreter::new(data, &mut out);

        let result = interp.run();

        match result {
            Ok(_) => {}
            Err(e) => {
                println!("{:?}", e);

                println!(
                    "pc after error: {}",
                    interp.memory.current_frame.program_counter
                );

                let manifest = interp.memory.manifest;
                println!(
                    "static_exe: {}..{}",
                    manifest.static_exe_start, manifest.static_exe_end
                );

                panic!("Failed");
            }
        }
    }
}
