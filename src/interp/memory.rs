use crate::util::*;
use crate::*;
use core::fmt::Write;
use core::mem;
use core::num::NonZeroU32;

const MAX_STACK_SIZE: u32 = 4 * 1024 * 1024;
const MAX_STACK_FRAMES: usize = 4000;

pub struct Memory {
    current_frame: StackFrame,

    stack_byte_size: u32,

    // eventually, this should be garbage-collected; probably should just
    // be a custom GC, don't try to make something generic
    memory: Pod<u8>,

    alloc_info: Pod<AllocInfo>,
    stack_pointer_map: Pod<u32>,
    stack_frames: Pod<StackFrame>,
}

#[derive(Clone, Copy)]
#[repr(C)]
pub struct Ptr {
    alloc_info_id: u32,
    offset: u32,
}

#[derive(Clone, Copy)]
struct StackFrame {
    expr: ExprId,
    program_counter: u32,
    map_offset: u32,
    begin: u32,
    word_len: u8,
}

// IDK why this is necessary, but before this struct was like 20 bytes, and now
// its 12. I thought using NonZeroU32 would make it better, but it did not.
// This is what we're using instead.
//                      - Albert Liu, Mar 12, 2022 Sat 22:47 EST
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

impl Memory {
    pub fn new() -> Self {
        return Self {
            current_frame: StackFrame {
                expr: ExprId::NULL,
                program_counter: 0,
                map_offset: 0,
                begin: 0,
                word_len: 0,
            },

            stack_byte_size: 0,

            memory: Pod::new(),
            alloc_info: Pod::new(),
            stack_frames: Pod::new(),
            stack_pointer_map: Pod::new(),
        };
    }

    pub fn alloc_stack_var(&mut self, len: u32) -> Result<(), Error> {
        if self.stack_byte_size.saturating_add(len) > MAX_STACK_SIZE {
            return Err(Error::new("stack overflow", self.loc()));
        }

        let begin = self.memory.len() as u32;

        self.memory.reserve(len as usize);
        for _ in 0..len {
            self.memory.push(0);
        }

        let (len, len_power) = compress_alloc_len(len);

        let alloc_info_id = self.alloc_info.len() as u32;

        self.alloc_info.push(AllocInfo::StackLive {
            create_expr: self.current_frame.expr,
            begin,
            len,
            len_power,
        });

        self.stack_pointer_map.push(alloc_info_id);

        return Ok(());
    }

    pub fn drop_stack_vars(&mut self, count: u32) -> Result<(), Error> {
        use AllocInfo::*;

        for _ in 0..count {
            if self.stack_pointer_map.len() <= self.current_frame.map_offset as usize {
                return Err(Error::new(
                    "internal error: over-popped from the stack",
                    self.loc(),
                ));
            }

            let mapped = self.stack_pointer_map.pop();
            let err = || Error::new("internal error: missing pointer map value", self.loc());
            let alloc_info_id = mapped.ok_or_else(err)?;

            let alloc_info = &mut self.alloc_info[alloc_info_id];
            match *alloc_info {
                StackLive {
                    create_expr,
                    begin,
                    len,
                    len_power,
                } => {
                    let len = decompress_alloc_len(len, len_power);
                    self.stack_byte_size -= len;

                    *alloc_info = StackDead {
                        create_expr,
                        destroy_expr: self.current_frame.expr,
                    };
                }

                _ => return Err(Error::new("internal error", self.loc())),
            }
        }

        return Ok(());
    }

    #[inline]
    pub fn next_op(&mut self) -> Result<(), Error> {
        return self.jmp(self.current_frame.program_counter + 1);
    }

    pub fn jmp(&mut self, id: u32) -> Result<(), Error> {
        // if id >= self.graph.ops.len() as u32 {
        //     return Err(Error::new("jump target invalid", self.loc()));
        // }

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

        let alloc_count = self.stack_pointer_map.len() as u32 - self.current_frame.map_offset;
        self.drop_stack_vars(alloc_count)?;

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

        let alloc_info_id = match self.stack_pointer_map.get(id) {
            Some(&info) => info,
            None => {
                return Err(Error::new("invalid stack pointer", self.loc()));
            }
        };

        return Ok(Ptr {
            alloc_info_id,
            offset,
        });
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

    pub fn write<T>(&mut self, ptr: Ptr, t: T) -> Result<(), Error>
    where
        T: Copy,
    {
        let bytes = any_as_u8_slice(&t);

        return self.write_bytes(ptr, bytes);
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

    pub fn memcpy(&mut self, dest: Ptr, src: Ptr, len: u32) -> Result<(), Error> {
        let dest_range = self.get_range(dest, len)?;
        let src_range = self.get_range(src, len)?;

        let src_ptr = &self.memory[src_range.start] as *const u8;
        let dest_ptr = &mut self.memory[dest_range.start] as *mut u8;

        unsafe { std::ptr::copy(src_ptr, dest_ptr, len as usize) };

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
        return self.current_frame.expr.loc();
    }
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

        let len = decompress_alloc_len(len, len_power);

        return Ok((expr, begin, len));
    }
}

#[inline]
fn decompress_alloc_len(len: u8, len_power: u8) -> u32 {
    let len = (len as u32) << len_power;

    return len;
}

#[inline]
fn compress_alloc_len(len: u32) -> (u8, u8) {
    let leading_zeros = len.leading_zeros() as u8;

    let len_power = (32 - leading_zeros).saturating_sub(8);
    let len = (len >> len_power) as u8;

    return (len, len_power);
}

unsafe fn any_as_u8_slice_mut<T: Sized + Copy>(p: &mut T) -> &mut [u8] {
    core::slice::from_raw_parts_mut(p as *mut T as *mut u8, mem::size_of::<T>())
}

fn any_as_u8_slice<T: Sized>(p: &T) -> &[u8] {
    unsafe { core::slice::from_raw_parts(p as *const T as *const u8, mem::size_of::<T>()) }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_alloc_len_compression() {
        let tests: &[u32] = &[
            0,
            1,
            2,
            3,
            4,
            5,
            128,
            255,
            256,
            255 * 2,
            230,
            1024,
            1024 * 1024,
            1024 * 1024 * 1024,
            255 << 30,
            255 << 24,
            255 << 23,
        ];

        for &input_len in tests {
            let (compress_len, len_power) = compress_alloc_len(input_len);

            let output_len = decompress_alloc_len(compress_len, len_power);

            assert_eq!(input_len, output_len);
        }
    }

    #[test]
    fn test_alloc_len_compression_lossy() {
        let tests: &[(u32, u32)] = &[
            ((255 << 20) + 1, 255 << 20),
            ((255 << 21) + 1, 255 << 21),
            ((255 << 22) + 1, 255 << 22),
            ((255 << 23) + 1, 255 << 23),
            ((255 << 23) + (1 << 22), 255 << 23),
        ];

        for &(input_len, expected_len) in tests {
            let (compress_len, len_power) = compress_alloc_len(input_len);

            let output_len = decompress_alloc_len(compress_len, len_power);

            assert_eq!(expected_len, output_len);
        }
    }

    #[test]
    fn type_sizing() {
        assert_eq!(mem::size_of::<AllocInfo>(), 12);
    }
}
