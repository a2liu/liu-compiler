use crate::*;

pub struct Assembler {
    pub exe_bytes: Pod<u32>,
    pub loc_bytes: Pod<ExprId>,
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

    pub fn assemble(mut self, graph: &Graph, entry_block: u32) -> AllocTracker {
        use GraphOpKind::*;

        let block = graph.blocks[entry_block];
        let ops = &graph.ops[block.ops];

        for &op in ops {
            self.current_expr = op.expr;

            match op.kind {
                DeclareStack { size } => {
                    let len = AllocLen::new(size as u32);
                    self.push(Opcode::StackAlloc {
                        len,
                        save_address: Out64Reg::NULL,
                    });
                }

                StackDealloc { count } => {
                    self.push(Opcode::StackDealloc { count });
                }

                ConstantU64 { target, value } => {
                    let register_out = Out64Reg::new(30);

                    self.push(Opcode::Make64 {
                        register_out,
                        stack_slot: StackSlot::MEH,
                    });

                    self.push(value as u32);
                    self.push((value >> 32) as u32);

                    self.write_to_operand(target, RegSize64, 30);
                }

                Mov { target, source } => {
                    let op = self.operand(source, 30);

                    self.write_to_operand(target, RegSize64, op);
                }

                Add {
                    target,
                    left,
                    right,
                } => {
                    let op1 = self.operand(left, 29);
                    let op2 = self.operand(right, 30);

                    self.push(Opcode::Add {
                        register_out: OutReg::new(RegUnsigned, RegSize64, 30),
                        left: InReg::new(RegSize64, op1 as u8),
                        right: InReg::new(RegSize64, op2 as u8),
                    });

                    self.write_to_operand(target, RegSize64, 30);
                }

                Print { value } => {
                    let op = self.operand(value, 30);

                    self.push(Opcode::Ecall {
                        kind: EcallKind::Print,
                        input_1: In64Reg::new(op),
                        input_2: In64Reg::NULL,
                    });
                }

                PrintNewline => {
                    self.push(Opcode::Ecall {
                        kind: EcallKind::PrintNewline,
                        input_1: In64Reg::NULL,
                        input_2: In64Reg::NULL,
                    });
                }

                ExitSuccess => {
                    self.push(Opcode::Ecall {
                        kind: EcallKind::ExitSuccess,
                        input_1: In64Reg::NULL,
                        input_2: In64Reg::NULL,
                    });
                }

                _ => {
                    unimplemented!("{:?}", op);
                }
            }
        }

        let mut binary = AllocTracker::new();
        binary.alloc_exe(self.exe_bytes, Some(self.loc_bytes));

        return binary;
    }

    pub fn write_to_operand(&mut self, op: Operand, size: RegSize, register: u8) {
        match op {
            Operand::StackLocal { id } => {
                self.push(Opcode::MakeFp {
                    register_out: Out64Reg::new(31),
                    stack_id: id,
                });

                // if offset != 0 {
                //     self.push(Opcode::Add16 {
                //         register_out: Out64Reg::new(31),
                //         value: offset,
                //     });
                // }

                self.push(Opcode::Set {
                    pointer: In64Reg::new(31),
                    value: InReg::new(size, register),
                });
            }

            Operand::RegisterValue { id } => {
                self.push(Opcode::Mov {
                    register_out: Out64Reg::new(id as u8),
                    register_in: In64Reg::new(register),
                });
            }

            Operand::Null => {
                panic!("oops");
            }
        }
    }

    pub fn operand(&mut self, op: Operand, temp_register: u8) -> u8 {
        match op {
            Operand::StackLocal { id } => {
                self.push(Opcode::MakeFp {
                    register_out: Out64Reg::new(31),
                    stack_id: id,
                });

                // if offset != 0 {
                //     self.push(Opcode::Add16 {
                //         register_out: Out64Reg::new(31),
                //         value: offset,
                //     });
                // }

                self.push(Opcode::Get {
                    pointer: In64Reg::new(31),
                    register_out: OutReg::new(RegUnsigned, RegSize64, temp_register),
                });

                return temp_register;
            }

            Operand::RegisterValue { id } => {
                return id as u8;
            }

            Operand::Null => {
                self.push(Opcode::Make16 {
                    register_out: OutReg::new(RegUnsigned, RegSize64, temp_register),
                    value: 0,
                });

                return temp_register;
            }
        }
    }

    pub fn push(&mut self, val: impl Into<u32>) {
        self.exe_bytes.push(val.into());
        self.loc_bytes.push(self.current_expr);
    }
}
