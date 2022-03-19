use crate::*;

pub struct Assembler {
    pub exe_bytes: Pod<u32>,
    pub loc_bytes: Pod<u32>,
    pub current_expr: ExprId,
}

impl Assembler {
    pub fn new() -> Self {
        return Self {
            exe_bytes: Pod::with_capacity(256),
            loc_bytes: Pod::with_capacity(256),
            current_expr: ExprId::NULL,
        };
    }

    pub fn assemble(&mut self, graph: &Graph, entry_block: u32) {
        use OpKind::*;
        use Operand::*;

        let block = graph.blocks[entry_block];

        let ops = &graph.ops[block.ops];

        let offset = block.ops.start as u32;
        let mut opcode_id = offset;
        for &op in ops {
            let register = (opcode_id + 1) as u8;
            match op {
                Loc { expr } => {
                    self.current_expr = expr;
                }

                StackVar { size } => {
                    let len = AllocLen::new(size);
                    self.push(Opcode::StackAlloc {
                        len,
                        save_address: Out64Reg::null(),
                    });
                }

                ConstantU64 { value } => {
                    self.push(Opcode::Make64 {
                        register_out: Out64Reg::new(register),
                        stack_slot: StackSlot::MEH,
                    });

                    self.push((value >> 32) as u32);
                    self.push(value as u32);
                }

                Store64 { pointer, value } => {
                    let value_register_id = match value {
                        OpResult { id } => (id - offset + 1) as u8,

                        _ => {
                            unimplemented!("{:?}", op);
                        }
                    };

                    match pointer {
                        ReferenceToStackLocal { id, offset } => {
                            self.push(Opcode::MakeFp {
                                register_out: Out64Reg::new(register),
                                stack_id: id,
                            });

                            if offset != 0 {
                                self.push(Opcode::Add16 {
                                    register_out: Out64Reg::new(register),
                                    value: offset,
                                });
                            }

                            self.push(Opcode::Set {
                                pointer: In64Reg::new(register),
                                value: InReg::new(RegSize64, value_register_id),
                            });
                        }
                        _ => {
                            unimplemented!("{:?}", op);
                        }
                    }
                }

                _ => {
                    unimplemented!("{:?}", op);
                }
            }
        }
    }

    pub fn push(&mut self, val: impl Into<u32>) {
        self.exe_bytes.push(val.into());

        let bytes = unsafe { core::mem::transmute(self.current_expr) };
        self.loc_bytes.push(bytes);
    }
}
