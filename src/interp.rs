use crate::util::*;
use crate::*;
use core::fmt::Write;
use std::collections::hash_map::HashMap;

pub fn interpret(graph: &Graph, stdout: &mut dyn Write) {}

#[derive(Debug, Clone, Copy)]
pub struct AllocInfo {
    pub created_loc: ExprId,
    pub destroyed_loc: ExprId,
    pub begin: u32,
    pub end: u32,
}

#[derive(Clone, Copy)]
pub struct StackFrame {
    callsite: ExprId,
    return_op: u32,
    alloc_info_offset: u32,
}

#[derive(Clone, Copy)]
#[repr(C)]
pub struct Ptr {
    alloc_info_id: u32,
    offset: u32,
}

const STACK_SIZE: u32 = 4 * 1024 * 1024;

pub struct Memory {
    pub memory: Pod<u8>,
    pub alloc_info: Pod<AllocInfo>,
    pub stack_frames: Pod<StackFrame>,
}

impl Memory {
    pub fn new() -> Self {
        return Self {
            memory: Pod::new(),
            alloc_info: Pod::new(),
            stack_frames: Pod::new(),
        };
    }
}
