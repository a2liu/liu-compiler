use crate::util::*;
use crate::*;
use core::fmt::Write;
use core::mem;
use core::num::NonZeroU32;

mod asm;
mod memory;
mod types;

pub use asm::*;
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
                StackAlloc { len, save_address } => {
                    let ptr = self.memory.alloc_stack_var(len)?;

                    if let Some(id) = save_address.id() {
                        self.memory.write_register(id, ptr)?;
                    }

                    self.memory.advance_pc();
                }

                StackDealloc { count } => {
                    self.memory.drop_stack_vars(count as u32)?;

                    self.memory.advance_pc();
                }

                Make64 {
                    register_out,
                    stack_slot,
                } => {
                    self.memory.advance_pc();

                    let low_order = self.memory.read_op()? as u64;
                    self.memory.advance_pc();

                    let high_order = self.memory.read_op()? as u64;

                    let value = (high_order << 32) | low_order;

                    if let Some(id) = register_out.id() {
                        self.memory.write_register(id, value)?;
                    } else {
                        let ptr = self.memory.stack_slot_ptr(stack_slot)?;
                        *self.memory.ptr_mut(ptr)? = value;
                    }

                    self.memory.advance_pc();
                }

                MakeFp {
                    register_out,
                    stack_id,
                } => {
                    let ptr = self.memory.stack_ptr(stack_id as u32, 0)?;

                    let id = register_out.expect_id()?;
                    self.memory.write_register(id, ptr)?;

                    self.memory.advance_pc();
                }

                Add {
                    register_out,
                    left,
                    right,
                } => {
                    let sign_extend = register_out.is_signed();
                    let out_size = register_out.size_class();

                    let result = if sign_extend {
                        let left = self.memory.read_signed_reg(left)?;
                        let right = self.memory.read_signed_reg(right)?;

                        let result = (left.wrapping_add(right)) as u64;

                        sign_extend_and_truncate(out_size, result) as u64
                    } else {
                        let left = self.memory.read_unsigned_reg(left)?;
                        let right = self.memory.read_unsigned_reg(right)?;

                        let result = left.wrapping_add(right);

                        truncate(out_size, result)
                    };

                    let out = register_out.expect_id()?;
                    self.memory.write_register(out, result)?;

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

        let value_2_16: u64 = 65536;
        let value_2_15: u64 = 32768;

        ops.push(
            StackAlloc {
                len: AllocLen::new(8),
                save_address: Out64Reg::new(1),
            }
            .into(),
        );

        ops.push(
            Make64 {
                register_out: Out64Reg::new(2),
                stack_slot: StackSlot { id: 0, offset: 0 },
            }
            .into(),
        );

        ops.push(value_2_16 as u32);
        ops.push(0);

        ops.push(
            Make64 {
                register_out: Out64Reg::new(3),
                stack_slot: StackSlot { id: 0, offset: 0 },
            }
            .into(),
        );

        ops.push(value_2_15 as u32);
        ops.push(0);

        ops.push(
            Add {
                register_out: OutReg::new(false, RegSize64, 4),
                left: InReg::new(RegSize16, 2),
                right: InReg::new(RegSize16, 3),
            }
            .into(),
        );

        ops.push(
            Add {
                register_out: OutReg::new(false, RegSize16, 5),
                left: InReg::new(RegSize16, 2),
                right: InReg::new(RegSize16, 3),
            }
            .into(),
        );

        ops.push(
            Add {
                register_out: OutReg::new(false, RegSize64, 6),
                left: InReg::new(RegSize16, 2),
                right: InReg::new(RegSize16, 3),
            }
            .into(),
        );

        ops.push(
            Add {
                register_out: OutReg::new(false, RegSize64, 7),
                left: InReg::new(RegSize64, 2),
                right: InReg::new(RegSize64, 3),
            }
            .into(),
        );

        ops.push(
            Add {
                register_out: OutReg::new(true, RegSize16, 8),
                left: InReg::new(RegSize64, 2),
                right: InReg::new(RegSize64, 3),
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

        assert_eq!(interp.memory.read_register(2).unwrap(), value_2_16);
        assert_eq!(interp.memory.read_register(3).unwrap(), value_2_15);
        assert_eq!(interp.memory.read_register(4).unwrap(), value_2_15);
        assert_eq!(interp.memory.read_register(5).unwrap(), value_2_15);
        assert_eq!(interp.memory.read_register(6).unwrap(), value_2_15);
        assert_eq!(
            interp.memory.read_register(7).unwrap(),
            value_2_16 + value_2_15
        );
        assert_eq!(
            interp.memory.read_register(8).unwrap(),
            value_2_15 as i16 as i64 as u64
        );

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
