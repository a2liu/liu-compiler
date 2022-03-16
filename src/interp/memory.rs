use crate::*;
use core::fmt::Write;
use core::mem;
use core::num::NonZeroU32;

const MAX_STACK_SIZE: u32 = 4 * 1024 * 1024;
const MAX_STACK_FRAMES: usize = 4000;

pub struct Memory {
    data: AllocTracker,

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

    // register block is always 32 * 8 = 256 bytes long
    registers_start: u32,
}

impl Memory {
    pub fn new(mut data: AllocTracker) -> Self {
        assert_eq!(
            any_as_u8_slice(&1u64),
            &[1u8, 0, 0, 0, 0, 0, 0, 0],
            "must be using little-endian platform"
        );

        // 256 bytes in compressed form
        let range = data.alloc_range(128, 1);

        let current_frame = StackFrame {
            program_counter: data.manifest.static_exe_start,
            map_offset: 0,
            registers_start: range.start,
        };

        return Self {
            data,

            stack_byte_size: 0,
            current_frame,

            stack_frames: Pod::new(),
            stack_pointer_map: Pod::new(),
        };
    }

    pub fn write_register(&mut self, id: u8, value: u64) -> Result<(), IError> {
        if id >= 32 {
            return Err(IError::new("invalid register value"));
        }

        let offset = self.current_frame.registers_start + id as u32;
        let ptr = &mut self.data.bytes[offset] as *mut u8 as *mut u64;

        unsafe { *ptr = value };

        return Ok(());
    }

    pub fn read_register(&self, id: u8) -> Result<u64, IError> {
        if id >= 32 {
            return Err(IError::new("invalid register value"));
        }

        let offset = self.current_frame.registers_start + id as u32;
        let ptr = &self.data.bytes[offset] as *const u8 as *const u64;

        return Ok(unsafe { *ptr });
    }

    pub fn alloc_stack_var(&mut self, len: u8, len_power: u8) -> Result<Ptr, IError> {
        let lossy_len = decompress_alloc_len(len, len_power);
        let new_stack_size = self.stack_byte_size.saturating_add(lossy_len);
        if new_stack_size > MAX_STACK_SIZE {
            return Err(IError::new("stack overflow"));
        }

        self.stack_byte_size = new_stack_size;

        let program_counter = self.current_frame.program_counter;
        let ptr = self.data.alloc_stack(len, len_power, program_counter);

        self.stack_pointer_map.push(ptr.alloc_info_id);

        return Ok(ptr);
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

    fn check_pc(&self, new_pc: u32) -> Result<(), IError> {
        if new_pc / 4 * 4 != new_pc {
            return Err(IError::new("internal error: program counter was unaligned"));
        }

        if new_pc < self.manifest.static_exe_start {
            return Err(IError::new("internal error: out-of-bounds of executable"));
        }

        if new_pc >= self.manifest.static_exe_end {
            return Err(IError::new("internal error: out-of-bounds of executable"));
        }

        return Ok(());
    }

    pub fn jmp(&mut self, new_pc: u32) -> Result<(), IError> {
        self.check_pc(new_pc)?;

        self.current_frame.program_counter = new_pc;

        return Ok(());
    }

    pub fn read_op(&self) -> Result<u32, IError> {
        let pc = self.current_frame.program_counter;

        self.check_pc(pc)?;

        let opcode_pointer = &self.data.bytes[pc] as *const u8 as *const u32;
        let opcode = unsafe { *opcode_pointer };

        return Ok(opcode);
    }

    pub fn advance_pc(&mut self) {
        self.current_frame.program_counter += 4;
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

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg_attr(target_arch = "x86_64", test)]
    fn endianess() {
        let data = AllocTracker::new();
        let memory = Memory::new(data);
    }
}
