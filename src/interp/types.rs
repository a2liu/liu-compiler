use crate::*;
use core::{fmt, mem};

pub struct IError {
    message: String,
}

impl IError {
    pub fn new(message: &str) -> Self {
        return Self {
            message: message.to_string(),
        };
    }
}

// Invariants:
//
// -    Opcodes are always 32-bit aligned; ExprId is stored in parallel array,
//      and since opcodes are always 32-bit aligned, we just use whichever
//      location cooresponds to the current program counter in the location arena
//
//      Why would we do it like this? Because accessing location information is
//      not the common case. If location information is stored in the same place
//      as the opcodes, close to half of the cache at any one point will be filled
//      with unhelpful location information.
//
//      Is this over-optimization? Maybe. But:
//      1.  Optimizing memory architecture after-the-fact is much harder than
//          designing it well to begin with
//      2.  This is a for-fun project, so go fuck yourself
//
// -    Registers are 64 bit, two's compliment. Register 0 is reserved for
//      the calling convention.
//
// -    For register-output:
//      -   Highest bit controls sign extend (set bit -> sign extend)
//      -   Next 2 bits control size (00 = 8bit, 01 = 16bit, 10 = 32bit, 11 = 64 bit)
//          writing a 8/16/32 bit value means either zeroing or sign-extending
//          the high order bytes
//      -   Next 5 bits decide the register ID, and an ID of 31 means NULL.
//
// -    For register-pointer-input/register-64-input:
//      -   Input size is always 64 bits
//      -   Highest bit is dummy
//      -   Next 2 bits are dummy
//      -   Next 5 bits decide the register ID, and an ID of 31 means NULL.
//
// -    For register-input:
//      -   Highest bit is dummy
//      -   Next 2 bits control size (00 = 8bit, 01 = 16bit, 10 = 32bit, 11 = 64 bit)
//          always read from lower-order bits when size is less than 64 bits
//      -   Next 5 bits decide the register ID, and an ID of 31 means NULL.
//
// -    In cases where an opcode accepts a stack-slot and a register-output, if the
//      register ID is null, the opcode result should be stored in the stack,
//      and otherwise should be stored in the register. The size bits on the
//      register flags should be used to determine write size
//
// -    For stack-slot:
//      -   First byte is the stack id
//      -   First byte is the offset into that id
//
// -    stack-id is a stack id
//
// -    In opcodes with a len-power and len, they combine to produce a 32 bit value,
//      using compression style from interp/memory.rs
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[non_exhaustive]
#[repr(u8)]
pub enum Opcode {
    Func, // opcode u8 u16

    StackAlloc,   // opcode u8-len-power u8-len u8
    StackDealloc, // opcode u8 u16-count
    HeapAlloc,    // opcode u8-register-output u8-register-64-input u8
    HeapDealloc,  // opcode u8-register-64-input u16

    Make16, // opcode u8-register-output u16-value
    Make32, // opcode u8-register-output u16-stack-slot u32-value
    Make64, // opcode u8-register-output u16-stack-slot u32-value-high-order-bits u32-low-order-bits
    MakeFp, // opcode u8-register-output u16-stack-id

    // in-place
    Truncate, // opcode u8-register-output u16-stack-slot
    BoolNorm, // opcode u8-register-output u16-stack-slot
    BoolNot,  // opcode u8-register-output u16-stack-slot

    Get, // opcode u8-register-output u8-register-pointer-input u8
    Set, // opcode u8-register-pointer-input u8-register-input u8

    // Register inputs are source, destination, length
    MemCopy, // opcode u8-register-pointer-input u8-register-pointer-input u8-register-64-input

    // Wrapping Integer operations
    // register-output signed-ness determines both the sign-extension of inputs
    // into 64 bits and also the operation signed-ness
    Add, // opcode u8-register-output u8-register-input u8-register-input
    Sub, // opcode u8-register-output u8-register-input u8-register-input
    Mul, // opcode u8-register-output u8-register-input u8-register-input
    Div, // opcode u8-register-output u8-register-input u8-register-input
    Mod, // opcode u8-register-output u8-register-input u8-register-input

    RShift, // opcode u8-register-output u8-register-input u8-register-input
    LShift, // opcode u8-register-output u8-register-input u8-register-input

    // Ignores signedness
    BitAnd, // opcode u8-register-output u8-register-input u8-register-input
    BitOr,  // opcode u8-register-output u8-register-input u8-register-input
    BitXor, // opcode u8-register-output u8-register-input u8-register-input
    BitNot, // opcode u8-register-output u8-register-input u8-register-input

    // Floating point
    FAdd, // opcode u8-register-output u8-register-input u8-register-input
    FSub, // opcode u8-register-output u8-register-input u8-register-input
    FMul, // opcode u8-register-output u8-register-input u8-register-input
    FDiv, // opcode u8-register-output u8-register-input u8-register-input
    FMod, // opcode u8-register-output u8-register-input u8-register-input

    // register-output size is implicitly ignored, because its not relevant here
    // register-output signed-ness determines both the sign-extension of inputs
    // into 64 bits and also the comparison signed-ness
    CompLt,  // opcode u8-register-output u8-register-input u8-register-input
    CompLeq, // opcode u8-register-output u8-register-input u8-register-input
    CompEq,  // opcode u8-register-output u8-register-input u8-register-input
    CompNeq, // opcode u8-register-output u8-register-input u8-register-input

    // The jumps here stays in the same allocation as they started in; the address
    // parameter only touches the offset part of the pointer
    Jump,          // opcode u8 u16 u32-address
    JumpIfZero,    // opcode u8-register-input u16-stack-slot u32-address
    JumpIfNotZero, // opcode u8-register-input u16-stack-slot u32-address

    Ret, // opcode u8 u16

    // args are allocated through stack allocs, then the call instruction sets
    // the frame pointer to the correct value using arg-count
    //
    // For functions that return a value larger than a single register, register
    // 0 is first read and used as the pointer location to store the return value
    // in, and register-output is unmodified. Otherwise, output is written to
    // register-output
    //
    // The jump here stays in the same allocation as it started in; the address
    // parameter only touches the offset part of the pointer
    Call, // opcode u8-register-output u8-arg-count u8 u32-address

    // Register inputs are interpreted differently depending on context
    Ecall, // opcode u8-ecall-type u8-register-64-input u8-register-64-input

    // Register inputs are string pointer and string length
    Throw, // opcode u8-skip-frames u8-register-input u8-register-64-input
}

#[derive(Clone, Copy)]
#[repr(C)]
pub struct Ptr {
    pub offset: u32,

    // This is 1-indexed so that NULL = 0 is always invalid
    pub alloc_info_id: u32,
}

#[derive(Clone, Copy)]

pub enum AllocKind {
    Stack,
    Heap,
}

// IDK why this is necessary, but before this struct was like 20 bytes, and now
// its 12. I thought using NonZeroU32 would make it better, but it did not.
// This is what we're using instead.
//                      - Albert Liu, Mar 12, 2022 Sat 22:47 EST
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum AllocInfo {
    StackLive {
        creation_op: u32,
        begin: u32,
        len: u8,
        len_power: u8,
    },
    StackDead {
        creation_op: u32,
        dealloc_op: u32,
    },

    HeapLive {
        creation_op: u32,
        begin: u32,
        len: u8,
        len_power: u8,
    },
    HeapDead {
        creation_op: u32,
        dealloc_op: u32,
    },

    // Executable, not read or writable
    StaticExe {
        begin: u32,
        len: u8,
        len_power: u8,
    },

    Static {
        creation_expr: ExprId,
        begin: u32,
        len: u8,
        len_power: u8,
    },
}

impl AllocInfo {
    pub fn get_range(self) -> Result<(u32, u32), IError> {
        use AllocInfo::*;

        #[rustfmt::skip]
        let (begin, len, len_power) = match self {
            StackLive { begin, len, len_power, .. }
            | HeapLive { begin, len, len_power, .. }
            | StaticExe { begin, len, len_power, }
            | Static { begin, len, len_power, .. } => {
                (begin, len, len_power)
            }

            StackDead { creation_op, dealloc_op, }
            | HeapDead { creation_op, dealloc_op, } => {
                return Err(IError::new("hello"));
            }
        };

        let len = decompress_alloc_len(len, len_power);

        return Ok((begin, len));
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct AllocTracker {
    // eventually, this should be garbage-collected; probably should just
    // be a custom GC, don't try to make something generic
    bytes: Pod<u8>,
    pub alloc_info: Pod<AllocInfo>,
}

impl AllocTracker {
    pub fn new() -> Self {
        // Use manifest at alloc_index=0
        Self {
            bytes: Pod::new(),
            alloc_info: Pod::new(),
        }
    }

    pub fn read_raw_op_bytes(&self, byte_index: u32) -> [u8; 4] {
        let mut bytes = [0u8; 4];

        bytes.copy_from_slice(&self.bytes[byte_index..(byte_index + 4)]);

        return bytes;
    }

    pub fn alloc(&mut self, kind: AllocKind, len: u32, creation_op: u32) -> (Ptr, u32) {
        use AllocInfo::*;
        use AllocKind::*;

        let begin = self.bytes.len() as u32;

        let (len, len_power) = compress_alloc_len(len);
        let lossy_len = decompress_alloc_len(len, len_power);
        self.bytes.reserve(lossy_len as usize);

        for _ in 0..lossy_len {
            self.bytes.push(0);
        }

        let info = match kind {
            Stack => StackLive {
                creation_op,
                begin,
                len,
                len_power,
            },
            Heap => HeapLive {
                creation_op,
                begin,
                len,
                len_power,
            },
        };

        self.alloc_info.push(info);

        let alloc_info_id = self.alloc_info.len() as u32;

        let ptr = Ptr {
            offset: 0,
            alloc_info_id,
        };

        return (ptr, lossy_len);
    }

    pub fn dealloc_stack(&mut self, ptr: Ptr, dealloc_op: u32) -> Result<u32, IError> {
        use AllocInfo::*;

        let alloc_info = self.get_alloc_info_mut(ptr)?;
        match *alloc_info {
            StackLive {
                creation_op,
                begin,
                len,
                len_power,
            } => {
                let len = decompress_alloc_len(len, len_power);

                *alloc_info = StackDead {
                    creation_op,
                    dealloc_op,
                };

                return Ok(len);
            }

            _ => return Err(IError::new("internal error")),
        }
    }

    pub fn ptr<T>(&self, ptr: Ptr) -> Result<&T, IError>
    where
        T: Copy,
    {
        let len = mem::size_of::<T>() as u32;
        let range = self.get_range(ptr, len)?;

        let ptr = &self.bytes[range.start] as *const u8 as *const T;

        return Ok(unsafe { &*ptr });
    }

    pub fn ptr_mut<T>(&mut self, ptr: Ptr) -> Result<&mut T, IError>
    where
        T: Copy,
    {
        let len = mem::size_of::<T>() as u32;
        let range = self.get_range(ptr, len)?;

        let ptr = &mut self.bytes[range.start] as *mut u8 as *mut T;

        return Ok(unsafe { &mut *ptr });
    }

    #[inline]
    pub fn read_bytes(&self, ptr: Ptr, len: u32) -> Result<&[u8], IError> {
        let range = self.get_range(ptr, len)?;
        return Ok(&self.bytes[range]);
    }

    #[inline]
    pub fn write_bytes(&mut self, ptr: Ptr, bytes: &[u8]) -> Result<(), IError> {
        let range = self.get_range(ptr, bytes.len() as u32)?;

        self.bytes[range].copy_from_slice(bytes);

        return Ok(());
    }

    pub fn memcpy(&mut self, dest: Ptr, src: Ptr, len: u32) -> Result<(), IError> {
        let dest_range = self.get_range(dest, len)?;
        let src_range = self.get_range(src, len)?;

        let src_ptr = &self.bytes[src_range.start] as *const u8;
        let dest_ptr = &mut self.bytes[dest_range.start] as *mut u8;

        unsafe { std::ptr::copy(src_ptr, dest_ptr, len as usize) };

        return Ok(());
    }

    pub fn get_alloc_info(&self, ptr: Ptr) -> Result<AllocInfo, IError> {
        if ptr.alloc_info_id == 0 {
            return Err(IError::new("null pointer"));
        }

        match self.alloc_info.get(ptr.alloc_info_id - 1) {
            Some(i) => return Ok(*i),
            None => {
                return Err(IError::new("invalid pointer"));
            }
        };
    }

    pub fn get_alloc_info_mut(&mut self, ptr: Ptr) -> Result<&mut AllocInfo, IError> {
        if ptr.alloc_info_id == 0 {
            return Err(IError::new("null pointer"));
        }

        match self.alloc_info.get_mut(ptr.alloc_info_id - 1) {
            Some(i) => return Ok(i),
            None => {
                return Err(IError::new("invalid pointer"));
            }
        };
    }

    pub fn get_range(&self, ptr: Ptr, len: u32) -> Result<CopyRange<u32>, IError> {
        let alloc_info = self.get_alloc_info(ptr)?;

        let (begin, alloc_len) = alloc_info.get_range()?;

        let ptr_end = ptr.offset + len;
        if ptr_end > alloc_len {
            return Err(IError::new("invalid pointer"));
        }

        return Ok(r(ptr.offset, ptr_end));
    }
}

#[inline]
pub fn decompress_alloc_len(len: u8, len_power: u8) -> u32 {
    let len = (len as u32) << len_power;

    return len;
}

#[inline]
pub fn compress_alloc_len(len: u32) -> (u8, u8) {
    let leading_zeros = len.leading_zeros() as u8;

    let len_power = (32 - leading_zeros).saturating_sub(8);
    let len = (len >> len_power) as u8;

    return (len, len_power);
}

pub unsafe fn any_as_u8_slice_mut<T: Sized + Copy>(p: &mut T) -> &mut [u8] {
    core::slice::from_raw_parts_mut(p as *mut T as *mut u8, mem::size_of::<T>())
}

pub fn any_as_u8_slice<T: Sized>(p: &T) -> &[u8] {
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
        assert_eq!(mem::size_of::<ExprId>(), 4);
    }
}
