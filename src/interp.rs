use crate::util::*;
use crate::*;
use core::fmt::Write;
use std::collections::hash_map::HashMap;

pub fn interpret(graph: &Graph, stdout: &mut dyn Write) {}

#[derive(Debug)]
pub struct AllocInfo {
    pub alloc_loc: ExprId,
    pub free_loc: ExprId,
    pub len: u32,
}

pub struct Memory {
    pub heap_data: Pod<u8>,
}
