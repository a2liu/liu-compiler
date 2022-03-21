use crate::*;
use core::cell::*;
use core::mem::*;
use core::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};

// bruh, idk what the deal is. idk what kind of system to use here. we'll figure
// it out later ig.

// during codegen we can use lifetime information to turn references to a stack
// local into op result references
#[derive(Debug, Clone, Copy)]
pub enum Operand {
    ReferenceToStackLocal { id: u16, offset: u16 },
    StackLocal { id: u16, offset: u16 },
    OpResult { id: u32 },
    Null,
}

#[derive(Debug, Clone, Copy)]
pub enum GraphOpKind {
    Loc {
        expr: ExprId,
    },

    ConstantU64 {
        output_id: u32,
        value: u64,
    },

    StackVar {
        // id: u32,
        size: u32,
    },

    StoreStack64 {
        stack_id: u16,
        offset: u16,
        input_id: u32,
    },

    Add64 {
        out: u32,
        op1: u32,
        op2: u32,
    },

    BuiltinPrint {
        op: Operand,
    },
    BuiltinNewline,

    // Control flow
    ExitSuccess,
}

#[derive(Clone, Copy)]
pub struct GraphOp {
    kind: GraphOpKind,
}

#[derive(Clone, Copy)]
pub struct BBInfo {
    pub ops: CopyRange<u32>,
    // pub is_ssa: bool,
}

pub struct Graph {
    pub ops: Pod<GraphOp>,
    pub blocks: Pod<BBInfo>,
    current_begin: u32,
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
        let end = self.ops.len() as u32;

        let id = self.blocks.len() as u32;

        let ops = r(begin, end);

        self.blocks.push(BBInfo { ops });

        return id;
    }

    pub fn loc(&mut self, expr: ExprId) {
        // self.ops.push(GraphOpKind::Loc { expr });
    }

    pub fn add(&mut self, op: GraphOp) {
        let id = self.ops.len() as u32;

        self.ops.push(op);
    }
}

/*

// TODO I want to make this system memory efficient, cache-friendly, and nice
// to use as a programmer. I cannot figure out how to do that. I guess I'll
// continue to rewrite this shit until that happens.
//
//                              - Albert Liu, Mar 20, 2022 Sun 21:22 EDT

#[derive(Clone, Copy)]
#[repr(transparent)]
pub struct Block(u32);

impl Block {
    pub fn new<A>(ops: Pod<GraphOp, A>) -> Self
    where
        A: Allocator,
    {
        let len = ops.len();
        let start = GRAPH.ops_len.fetch_add(len, Ordering::SeqCst);

        if start.saturating_add(len) >= GRAPH.ops_capacity as usize {
            panic!("rippo");
        }

        let start = start as u32;
        let len = len as u32;

        let range = r(start, start + len);

        let block_id = GRAPH.blocks_len.fetch_add(1, Ordering::SeqCst);
        if block_id >= GRAPH.blocks_capacity as usize {
            panic!("rippo");
        }

        unsafe {
            let block = &mut *(GRAPH.blocks.add(start as usize) as *mut BlockInfo);

            let range_as_u64: u64 = core::mem::transmute(range);

            block.ops_data.store(range_as_u64, Ordering::SeqCst);
        }

        return Self(block_id as u32);
    }
}

pub struct BlockInfo {
    ops_data: AtomicU64,
    // pub is_ssa: bool,
}

impl BlockInfo {
    pub fn ops(&self) -> &[GraphOp] {
        let data = self.ops_data.load(Ordering::SeqCst);

        let range: CopyRange<u32> = unsafe { core::mem::transmute(data) };
        let len = range.end - range.start;

        let ops = GRAPH.ops as *mut GraphOp;

        unsafe {
            let ops = ops.add(range.start as usize);
            let ops = core::slice::from_raw_parts(ops, len as usize);

            return ops;
        }
    }
}

struct GraphAllocator {
    ops_capacity: u32,
    ops: *const GraphOp,
    ops_len: AtomicUsize,

    free_block: u32,

    blocks_capacity: u32,
    blocks: *const BlockInfo,
    blocks_len: AtomicUsize,
}

unsafe impl Sync for GraphAllocator {}

lazy_static! {
    static ref GRAPH: GraphAllocator = {
        let ops = unsafe { map_region(core::ptr::null(), 100) }.unwrap();
        let ops = ops as *const GraphOp;

        let blocks = unsafe { map_region(core::ptr::null(), 100) }.unwrap();
        let blocks = blocks as *const BlockInfo;

        GraphAllocator {
            ops_capacity: 0,
            ops,
            ops_len: AtomicUsize::new(0),

            free_block: 0,

            blocks_capacity: 0,
            blocks,
            blocks_len: AtomicUsize::new(0),
        }
    };
}
*/
