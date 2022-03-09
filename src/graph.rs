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

#[derive(Clone, Copy)]
pub enum Value {
    StackLocal { id: u32 },
    OpResult { id: u32 },
}

#[derive(Clone, Copy)]
pub enum OpKind {
    // Stores: no output value
    StackStore { offset: u16, size: u8, value: Value },
    Store8 { pointer: Value, value: Value },
    Store16 { pointer: Value, value: Value },
    Store32 { pointer: Value, value: Value },
    Store64 { pointer: Value, value: Value },

    StackLoad { offset: u16, size: u8 },
    Load8 { location: Value },
    Load16 { location: Value },
    Load32 { location: Value },
    Load64 { location: Value },

    Forward { block_input_id: u32, id: Value },
    BlockInput {},

    Add { op1: Value, op2: Value },
}

#[derive(Clone, Copy)]
pub struct BBTag {
    pub end_op: ControlKind,
}

pub struct Graph<'a> {
    pub blocks: Vec<HeapArray<BBTag, OpKind, &'a BucketList>>,
}
