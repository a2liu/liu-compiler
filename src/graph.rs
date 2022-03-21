use crate::*;
use core::cell::*;
use core::mem::*;
use core::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};

// bruh, idk what the deal is. idk what kind of system to use here. we'll figure
// it out later ig.

#[derive(Debug, Clone, Copy)]
pub enum GraphOp {
    Loc(ExprId),

    ConstantU32 {
        output_id: u32,
        value: u32,
    },
    ConstantU64 {
        output_id: u32,
        value: u64,
    },

    StackVar {
        // id: u32,
        size: u32,
    },

    LoadStack64 {
        output_id: u32,
        stack_id: u16,
        offset: u16,
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
        op: u32,
    },
    BuiltinNewline,

    // Control flow
    ExitSuccess,
}

#[derive(Clone, Copy)]
pub struct BBInfo {
    pub ops: CopyRange<u32>,
    // pub is_ssa: bool,
}

pub struct Graph {
    pub ops: Pod<GraphOp>,
    pub blocks: Pod<BBInfo>,
}

impl Graph {
    pub fn new() -> Self {
        return Graph {
            ops: Pod::new(),
            blocks: Pod::new(),
        };
    }

    pub fn get_block_id(&mut self) -> u32 {
        let id = self.blocks.len() as u32;

        self.blocks.push(BBInfo { ops: r(0, 0) });

        return id;
    }

    pub fn write_block(&mut self, id: u32, ops: Pod<GraphOp>) {
        let start = self.ops.len() as u32;

        self.ops.reserve(ops.len());

        for op in ops {
            self.ops.push(op);
        }

        let end = self.ops.len() as u32;

        self.blocks[id] = BBInfo { ops: r(start, end) };
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
