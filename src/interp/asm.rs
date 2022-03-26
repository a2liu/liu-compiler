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

        /*
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
                        let (id_opt, stack_slot) = self.stack_or_register_target(target);

                        let make = |id: u8| Out64Reg::new(id);
                        let register_out = id_opt.map(make).unwrap_or(Out64Reg::NULL);

                        self.push(Opcode::Make64 {
                            register_out,
                            stack_slot,
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

                    Print { value } => {
                        let op = self.operand(value);

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
        */

        let mut binary = AllocTracker::new();
        binary.alloc_exe(self.exe_bytes, Some(self.loc_bytes));

        return binary;
    }

    pub fn operand(&mut self, op: Operand) -> u8 {
        return 0;
    }

    pub fn push(&mut self, val: impl Into<u32>) {
        self.exe_bytes.push(val.into());
        self.loc_bytes.push(self.current_expr);
    }
}
