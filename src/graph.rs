use crate::*;
use core::cell::*;
use core::mem::*;
use core::sync::atomic::{AtomicUsize, Ordering};

// bruh, idk what the deal is. idk what kind of system to use here. we'll figure
// it out later ig.

// during codegen we can use lifetime information to turn references to a stack
// local into op result references
#[derive(Debug, Clone, Copy)]
pub enum Operand {
    ReferenceToStackLocal { id: u32, offset: u16 },
    StackLocal { id: u32 },
    OpResult { id: u32 },
    ConstantU64 { value: u64 },
}

#[derive(Debug, Clone, Copy)]
pub enum OpKind {
    Loc {
        expr: ExprId,
    },

    // Stores: no output value
    Store8 {
        pointer: Operand,
        value: Operand,
    },
    Store16 {
        pointer: Operand,
        value: Operand,
    },
    Store32 {
        pointer: Operand,
        value: Operand,
    },
    Store64 {
        pointer: Operand,
        value: Operand,
    },

    Load8 {
        pointer: Operand,
    },
    Load16 {
        pointer: Operand,
    },
    Load32 {
        pointer: Operand,
    },
    Load64 {
        pointer: Operand,
    },

    // SSA block parameter/phi node stuff
    Forward {
        block_input_id: u32,
        id: Operand,
    },
    BlockInput {},

    Add64 {
        op1: Operand,
        op2: Operand,
    },

    BuiltinPrint {
        op: Operand,
    },
    BuiltinNewline,

    // Control flow
    BranchNeqZero {
        conditional: u32,
        block_if_true: u32,
        block_if_false: u32,
    },
    ExitSuccess,
    Jump {
        block: u32,
    },
}

#[derive(Clone, Copy)]
pub struct BBInfo {
    pub ops: CopyRange,
}

pub struct Graph {
    pub ops: Pod<OpKind>,
    pub blocks: Pod<BBInfo>,
    current_begin: usize,
}

impl Graph {
    pub fn new() -> Self {
        return Graph {
            ops: Pod::new(),
            blocks: Pod::new(),
            current_begin: 0,
        };
    }

    pub fn complete_block(&mut self) -> u32 {
        let begin = self.current_begin;
        let end = self.ops.len();

        let id = self.blocks.len() as u32;

        let ops = r(begin, end);

        self.blocks.push(BBInfo { ops });

        return id;
    }

    pub fn loc(&mut self, expr: ExprId) {
        self.ops.push(OpKind::Loc { expr });
    }

    pub fn add(&mut self, op: OpKind) -> Operand {
        let id = self.ops.len() as u32;

        self.ops.push(op);

        return Operand::OpResult { id };
    }
}
