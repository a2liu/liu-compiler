use crate::*;
use core::fmt::Write;
use core::mem;
use core::num::NonZeroU32;

const MAX_STACK_SIZE: u32 = 4 * 1024 * 1024;
const MAX_STACK_FRAMES: usize = 4000;

pub struct Memory {
    data: AllocTracker,

    // bounds of static exe allocation, use these to calculate program counter
    // and do bounds checking
    static_exe_begin: u32,
    static_exe_end: u32,

    stack_byte_size: u32,
    current_frame: StackFrame,

    stack_pointer_map: Pod<u32>,
    stack_frames: Pod<StackFrame>,
}

impl core::ops::Deref for Memory {
    type Target = AllocTracker;

    fn deref(&self) -> &Self::Target {
        return &self.data;
    }
}

impl core::ops::DerefMut for Memory {
    fn deref_mut(&mut self) -> &mut Self::Target {
        return &mut self.data;
    }
}

#[derive(Clone, Copy)]
struct StackFrame {
    program_counter: u32,
    map_offset: u32,
    begin: u32,
    word_len: u8,
}

impl Memory {
    pub fn new() -> Self {
        assert_eq!(
            any_as_u8_slice(&1u64),
            &[1u8, 0, 0, 0, 0, 0, 0, 0],
            "must be using little-endian platform"
        );

        // TODO parse the binary

        return Self {
            data: AllocTracker::new(),

            static_exe_begin: 0,
            static_exe_end: 0,
            stack_byte_size: 0,
            current_frame: StackFrame {
                // TODO use real info
                program_counter: 0,
                map_offset: 0,
                begin: 0,
                word_len: 0,
            },

            stack_frames: Pod::new(),
            stack_pointer_map: Pod::new(),
        };
    }

    pub fn alloc_stack_var(&mut self, len: u32) -> Result<(), IError> {
        if self.stack_byte_size.saturating_add(len) > MAX_STACK_SIZE {
            return Err(IError::new("stack overflow"));
        }

        let program_counter = self.current_frame.program_counter;
        let (ptr, len) = self.data.alloc(AllocKind::Stack, len, program_counter);

        self.stack_pointer_map.push(ptr.alloc_info_id);

        return Ok(());
    }

    pub fn drop_stack_vars(&mut self, count: u32) -> Result<(), IError> {
        use AllocInfo::*;

        for _ in 0..count {
            if self.stack_pointer_map.len() <= self.current_frame.map_offset as usize {
                return Err(IError::new("internal error: over-popped from the stack"));
            }

            let mapped = self.stack_pointer_map.pop();
            let err = || IError::new("internal error: missing pointer map value");
            let alloc_info_id = mapped.ok_or_else(err)?;

            let ptr = Ptr {
                alloc_info_id,
                offset: 9,
            };

            let len = self.data.dealloc_stack(ptr)?;
            self.stack_byte_size -= len;
        }

        return Ok(());
    }

    #[inline]
    pub fn next_op(&mut self) -> Result<(), IError> {
        return self.jmp(self.current_frame.program_counter + 1);
    }

    pub fn jmp(&mut self, id: u32) -> Result<(), IError> {
        // if id >= self.graph.ops.len() as u32 {
        //     return Err(IError::new("jump target invalid"));
        // }

        self.current_frame.program_counter = id;

        return Ok(());
    }

    pub fn ret(&mut self) -> Result<(), IError> {
        let previous = match self.stack_frames.pop() {
            Some(p) => p,
            None => {
                return Err(IError::new("no frames left"));
            }
        };

        let alloc_count = self.stack_pointer_map.len() as u32 - self.current_frame.map_offset;
        self.drop_stack_vars(alloc_count)?;

        self.current_frame = previous;

        return Ok(());
    }

    pub fn call(&mut self, new_pc: u32) -> Result<(), IError> {
        if self.stack_frames.len() >= MAX_STACK_FRAMES {
            return Err(IError::new("recursion limit reached"));
        }

        self.stack_frames.push(self.current_frame);

        self.current_frame.program_counter = new_pc;
        self.current_frame.map_offset = self.stack_pointer_map.len() as u32;

        return Ok(());
    }

    pub fn stack_ptr(&self, id: u32, offset: u32) -> Result<Ptr, IError> {
        let id = self.current_frame.map_offset + id;

        let alloc_info_id = match self.stack_pointer_map.get(id) {
            Some(&info) => info,
            None => {
                return Err(IError::new("invalid stack pointer"));
            }
        };

        return Ok(Ptr {
            alloc_info_id,
            offset,
        });
    }
}
