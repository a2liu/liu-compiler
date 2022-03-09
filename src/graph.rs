use crate::util::*;
use crate::*;
use core::cell::*;
use core::mem::*;
use core::sync::atomic::{AtomicUsize, Ordering};

// bruh, idk what the deal is. idk what kind of system to use here. we'll figure
// it out later ig.

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

pub enum OpKind {
    // Stores: no output value
    StackStore { offset: u16, size: u8, id: u32 },
    Store8 { location_id: u32, value_id: u32 },
    Store16 { location_id: u32, value_id: u32 },
    Store32 { location_id: u32, value_id: u32 },
    Store64 { location_id: u32, value_id: u32 },

    StackLoad { offset: u16, size: u8 },
    Load8 { location_id: u32 },
    Load16 { location_id: u32 },
    Load32 { location_id: u32 },
    Load64 { location_id: u32 },

    Forward { block_input_id: u32, id: u32 },
    BlockInput {},

    Add { op1: u32, op2: u32 },
}

pub struct BasicBlock {
    ops: [OpKind],
}

pub struct Graph {}
