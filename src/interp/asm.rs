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
        use GraphOp::*;

        let block = graph.blocks[entry_block];
        let ops = &graph.ops[block.ops];

        for &op in ops {
            /*
            match op {
                Loc(id) => {
                    self.current_expr = id;
                }

                StackVar { size } => {
                    let len = AllocLen::new(size);
                    self.push(Opcode::StackAlloc {
                        len,
                        save_address: Out64Reg::NULL,
                    });
                }
                StackDealloc { count } => {
                    self.push(Opcode::StackDealloc { count });
                }

                ConstantU64 { output_id, value } => {
                    self.push(Opcode::Make64 {
                        register_out: Out64Reg::new(output_id as u8),
                        stack_slot: StackSlot::MEH,
                    });

                    self.push(value as u32);
                    self.push((value >> 32) as u32);
                }

                StoreStack64 {
                    stack_id,
                    offset,
                    input_id,
                } => {
                    self.push(Opcode::MakeFp {
                        register_out: Out64Reg::new(31),
                        stack_id,
                    });

                    if offset != 0 {
                        self.push(Opcode::Add16 {
                            register_out: Out64Reg::new(31),
                            value: offset,
                        });
                    }

                    self.push(Opcode::Set {
                        pointer: In64Reg::new(31),
                        value: InReg::new(RegSize64, input_id as u8),
                    });
                }

                LoadStack64 {
                    output_id,
                    stack_id,
                    offset,
                } => {
                    self.push(Opcode::MakeFp {
                        register_out: Out64Reg::new(31),
                        stack_id,
                    });

                    if offset != 0 {
                        self.push(Opcode::Add16 {
                            register_out: Out64Reg::new(31),
                            value: offset,
                        });
                    }

                    self.push(Opcode::Get {
                        register_out: OutReg::new(RegUnsigned, RegSize64, output_id as u8),
                        pointer: In64Reg::new(31),
                    });
                }

                Add64 { out, op1, op2 } => {
                    self.push(Opcode::Add {
                        register_out: OutReg::new(RegUnsigned, RegSize64, out as u8),
                        left: InReg::new(RegSize64, op1 as u8),
                        right: InReg::new(RegSize64, op2 as u8),
                    });
                }

                BuiltinPrint { op } => {
                    self.push(Opcode::Ecall {
                        kind: EcallKind::Print,
                        input_1: In64Reg::new(op as u8),
                        input_2: In64Reg::NULL,
                    });
                }

                BuiltinNewline => {
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

            */
        }

        let mut binary = AllocTracker::new();
        binary.alloc_exe(self.exe_bytes, Some(self.loc_bytes));

        return binary;
    }

    pub fn push(&mut self, val: impl Into<u32>) {
        self.exe_bytes.push(val.into());
        self.loc_bytes.push(self.current_expr);
    }
}
