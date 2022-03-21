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

            // println!("{:?}", opcode);

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
                        self.memory.write(ptr, value)?;
                    }

                    self.memory.advance_pc();
                }

                MakeFp {
                    register_out,
                    stack_id,
                } => {
                    let ptr = self.memory.stack_ptr(stack_id as u32, 0)?;

                    println!("MakeFp {}", stack_id);

                    let id = register_out.expect_id()?;
                    self.memory.write_register(id, ptr)?;

                    self.memory.advance_pc();
                }

                Set { pointer, value } => {
                    let size_class = value.size_class();
                    let pointer: Ptr = self.memory.read_unsigned_reg(pointer)?.into();

                    let value: u64 = self.memory.read_unsigned_reg(value)?.into();

                    println!("set {:?} {}", pointer, value);

                    match size_class {
                        0 => self.memory.write(pointer, value as u8)?,
                        1 => self.memory.write(pointer, value as u16)?,
                        2 => self.memory.write(pointer, value as u32)?,
                        3 => self.memory.write(pointer, value as u64)?,
                        _ => {
                            panic!("invalid size class: {}", size_class);
                        }
                    };

                    self.memory.advance_pc();
                }

                Get {
                    register_out,
                    pointer,
                } => {
                    let pointer: Ptr = self.memory.read_unsigned_reg(pointer)?.into();

                    let out_size = register_out.size_class();

                    let value = match out_size {
                        0 => self.memory.read::<u8>(pointer)? as u64,
                        1 => self.memory.read::<u16>(pointer)? as u64,
                        2 => self.memory.read::<u32>(pointer)? as u64,
                        3 => self.memory.read::<u64>(pointer)? as u64,
                        _ => {
                            panic!("invalid size class: {}", out_size);
                        }
                    };

                    println!("get {:?} {}", pointer, value);

                    let id = register_out.expect_id()?;

                    let value = if register_out.is_signed() {
                        sign_extend_and_truncate(out_size, value) as u64
                    } else {
                        truncate(out_size, value) as u64
                    };

                    self.memory.write_register(id, value)?;

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

                Ecall {
                    kind,
                    input_1,
                    input_2,
                } => match kind {
                    EcallKind::ExitSuccess => break,
                    EcallKind::Print => {
                        let left = self.memory.read_unsigned_reg(input_1)?;

                        let err = |_| IError::new("failed to write");
                        write!(self.out, "{} ", left).map_err(err)?;

                        self.memory.advance_pc();
                    }
                    EcallKind::PrintNewline => {
                        let err = |_| IError::new("failed to write");
                        self.out.write_str("\n").map_err(err)?;

                        self.memory.advance_pc();
                    }

                    #[allow(unreachable_patterns)]
                    _ => {
                        panic!("invalid kind {}", kind as u8);
                    }
                },

                _ => {
                    unimplemented!("{:?}", opcode);
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
                register_out: OutReg::new(RegUnsigned, RegSize64, 4),
                left: InReg::new(RegSize16, 2),
                right: InReg::new(RegSize16, 3),
            }
            .into(),
        );

        ops.push(
            Add {
                register_out: OutReg::new(RegUnsigned, RegSize16, 5),
                left: InReg::new(RegSize16, 2),
                right: InReg::new(RegSize16, 3),
            }
            .into(),
        );

        ops.push(
            Add {
                register_out: OutReg::new(RegUnsigned, RegSize64, 6),
                left: InReg::new(RegSize16, 2),
                right: InReg::new(RegSize16, 3),
            }
            .into(),
        );

        ops.push(
            Add {
                register_out: OutReg::new(RegUnsigned, RegSize64, 7),
                left: InReg::new(RegSize64, 2),
                right: InReg::new(RegSize64, 3),
            }
            .into(),
        );

        ops.push(
            Add {
                register_out: OutReg::new(RegSigned, RegSize16, 8),
                left: InReg::new(RegSize64, 2),
                right: InReg::new(RegSize64, 3),
            }
            .into(),
        );

        ops.push(StackDealloc { count: 1 }.into());

        ops.push(
            Ecall {
                kind: EcallKind::ExitSuccess,
                input_1: In64Reg::NULL,
                input_2: In64Reg::NULL,
            }
            .into(),
        );

        data.alloc_exe(ops, None);

        let mut out = String::new();

        let mut interp = Interpreter::new(data, &mut out);

        let result = interp.run();

        let sum = value_2_16 + value_2_15;
        let sign_extended = value_2_15 as i16 as i64 as u64;
        assert_eq!(interp.memory.read_register(2).unwrap(), value_2_16);
        assert_eq!(interp.memory.read_register(3).unwrap(), value_2_15);
        assert_eq!(interp.memory.read_register(4).unwrap(), value_2_15);
        assert_eq!(interp.memory.read_register(5).unwrap(), value_2_15);
        assert_eq!(interp.memory.read_register(6).unwrap(), value_2_15);
        assert_eq!(interp.memory.read_register(7).unwrap(), sum);
        assert_eq!(interp.memory.read_register(8).unwrap(), sign_extended);

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
