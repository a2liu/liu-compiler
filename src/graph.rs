use crate::util::*;
use crate::*;
use core::cell::*;
use core::mem::*;
use core::sync::atomic::{AtomicUsize, Ordering};

// bruh, idk what the deal is. idk what kind of system to use here. we'll figure
// it out later ig.

#[derive(Clone, Copy)]
pub enum ControlKind {
    BranchNeqZero {
        conditional: u32,
        id_if_true: u32,
        id_if_false: u32,
    },
    Jump {
        id: u32,
    },
}

// during codegen we can use lifetime information to turn references to a stack
// local into op result references
#[derive(Clone, Copy)]
pub enum Value {
    ReferenceToStackLocal { id: u32, offset: u16 },
    StackLocal { id: u32 },
    OpResult { id: u32 },
}

#[derive(Clone, Copy)]
pub enum OpKind {
    // Stores: no output value
    Store8 { pointer: Value, value: Value },
    Store16 { pointer: Value, value: Value },
    Store32 { pointer: Value, value: Value },
    Store64 { pointer: Value, value: Value },

    Load8 { location: Value },
    Load16 { location: Value },
    Load32 { location: Value },
    Load64 { location: Value },

    // SSA block parameter/phi node stuff
    Forward { block_input_id: u32, id: Value },
    BlockInput {},

    Add { op1: Value, op2: Value },
}

#[derive(Clone, Copy)]
pub struct BBInfo {
    pub end_op: ControlKind,
    pub ops: CopyRange,
}

pub struct Graph {
    pub source: Pod<ExprId>,
    pub ops: Pod<OpKind>,
    pub blocks: Pod<BBInfo>,
}
