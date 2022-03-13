use crate::util::*;
use crate::*;
use core::fmt::Write;
use core::mem;
use core::num::NonZeroU32;
use std::collections::hash_map::HashMap;

const STACK_SIZE: u32 = 4 * 1024 * 1024;
const MAX_STACK_FRAMES: usize = 4000;

pub fn interpret(graph: &Graph, stdout: &mut dyn Write) {}

#[derive(Debug, Clone, Copy)]
pub enum AllocInfo {
    StackLive {
        create_expr: ExprId,
        begin: u32,
        len: u8,
        len_power: u8,
    },
    StackDead {
        create_expr: ExprId,
        destroy_expr: ExprId,
    },

    HeapLive {
        create_expr: ExprId,
        begin: u32,
        len: u8,
        len_power: u8,
    },
    HeapDead {
        create_expr: ExprId,
        destroy_expr: ExprId,
    },

    StaticLive {
        create_expr: ExprId,
        begin: u32,
        len: u8,
        len_power: u8,
    },
    StaticDead {
        create_expr: ExprId,
        destroy_expr: ExprId,
    },
}

impl AllocInfo {
    fn get_range(self) -> Result<(ExprId, u32, u32), Error> {
        use AllocInfo::*;

        #[rustfmt::skip]
        let (expr,begin, len, len_power) = match self {
            StackLive { create_expr, begin, len, len_power, }
            | HeapLive { create_expr, begin, len, len_power, }
            | StaticLive { create_expr, begin, len, len_power, } => {
                (create_expr,begin, len, len_power)
            }

            StackDead { create_expr, destroy_expr, }
            | HeapDead { create_expr, destroy_expr, }
            | StaticDead { create_expr, destroy_expr, } => {
                return Err(Error::new("hello", create_expr.loc()));
            }
        };

        let len = (len as u32) << len_power;

        return Ok((expr, begin, len));
    }
}

#[derive(Clone, Copy)]
pub struct StackFrame {
    program_counter: u32,
    map_offset: u32,
}

#[derive(Clone, Copy)]
#[repr(C)]
pub struct Ptr {
    alloc_info_id: u32,
    offset: u32,
}

pub struct Memory {
    graph: Graph,
    current_frame: StackFrame,

    memory: Pod<u8>,
    alloc_info: Pod<AllocInfo>,
    stack_pointer_map: Pod<u32>,
    stack_frames: Pod<StackFrame>,
}

impl Memory {
    pub fn new(graph: Graph) -> Self {
        return Self {
            graph,
            current_frame: StackFrame {
                program_counter: 0,
                map_offset: 0,
            },

            memory: Pod::new(),
            alloc_info: Pod::new(),
            stack_frames: Pod::new(),
            stack_pointer_map: Pod::new(),
        };
    }

    #[inline]
    pub fn read_op(&self) -> OpKind {
        return self.graph.ops[self.current_frame.program_counter];
    }

    #[inline]
    pub fn next_op(&mut self) -> Result<(), Error> {
        return self.jmp(self.current_frame.program_counter + 1);
    }

    pub fn jmp(&mut self, id: u32) -> Result<(), Error> {
        if id >= self.graph.ops.len() as u32 {
            return Err(Error::new("jump target invalid", self.loc()));
        }

        self.current_frame.program_counter = id;

        return Ok(());
    }

    pub fn ret(&mut self) -> Result<(), Error> {
        let previous = match self.stack_frames.pop() {
            Some(p) => p,
            None => {
                return Err(Error::new("no frames left", self.loc()));
            }
        };

        self.current_frame = previous;

        return Ok(());
    }

    pub fn call(&mut self, new_pc: u32) -> Result<(), Error> {
        if self.stack_frames.len() >= MAX_STACK_FRAMES {
            return Err(Error::new("recursion limit reached", self.loc()));
        }

        self.stack_frames.push(self.current_frame);

        self.current_frame.program_counter = new_pc;
        self.current_frame.map_offset = self.stack_pointer_map.len() as u32;

        return Ok(());
    }

    pub fn stack_ptr(&self, id: u32, offset: u32) -> Result<Ptr, Error> {
        let id = self.current_frame.map_offset + id;

        return match self.stack_pointer_map.get(id) {
            Some(&alloc_info_id) => Ok(Ptr {
                alloc_info_id,
                offset,
            }),
            None => {
                return Err(Error::new("invalid stack pointer", self.loc()));
            }
        };
    }

    pub fn read<T>(&self, ptr: Ptr) -> Result<T, Error>
    where
        T: Copy,
    {
        let len = mem::size_of::<T>() as u32;
        let from_bytes = self.read_bytes(ptr, len)?;

        let mut out = mem::MaybeUninit::uninit();
        unsafe { any_as_u8_slice_mut(&mut out).copy_from_slice(from_bytes) };
        return Ok(unsafe { out.assume_init() });
    }

    #[inline]
    pub fn read_bytes(&self, ptr: Ptr, len: u32) -> Result<&[u8], Error> {
        let range = self.get_range(ptr, len)?;
        return Ok(&self.memory[range]);
    }

    #[inline]
    pub fn write_bytes(&mut self, ptr: Ptr, bytes: &[u8]) -> Result<(), Error> {
        let range = self.get_range(ptr, bytes.len() as u32)?;

        self.memory[range].copy_from_slice(bytes);

        return Ok(());
    }

    pub fn get_range(&self, ptr: Ptr, len: u32) -> Result<CopyRange<u32>, Error> {
        let alloc_info = match self.alloc_info.get(ptr.alloc_info_id) {
            Some(i) => *i,
            None => {
                return Err(Error::new("invalid pointer", self.loc()));
            }
        };

        let (expr, begin, alloc_len) = alloc_info.get_range()?;

        let ptr_end = ptr.offset + len;
        if ptr_end > alloc_len {
            return Err(Error::new("invalid pointer", self.loc()));
        }

        return Ok(r(ptr.offset, ptr_end));
    }

    pub fn loc(&self) -> CodeLoc {
        let expr = self.graph.source[self.current_frame.program_counter];
        return expr.loc();
    }
}

unsafe fn any_as_u8_slice_mut<T: Sized + Copy>(p: &mut T) -> &mut [u8] {
    core::slice::from_raw_parts_mut(p as *mut T as *mut u8, mem::size_of::<T>())
}

fn any_as_u8_slice<T: Sized>(p: &T) -> &[u8] {
    unsafe { core::slice::from_raw_parts(p as *const T as *const u8, mem::size_of::<T>()) }
}
