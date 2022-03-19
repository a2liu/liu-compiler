use crate::*;
use core::{fmt, mem};

#[derive(Debug)]
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

#[derive(Debug, Clone, Copy)]
#[repr(u8)]
pub enum RegSignedness {
    RegUnsigned = 0,
    RegSigned = 1,
}

#[derive(Debug, Clone, Copy)]
#[repr(u8)]
pub enum RegSize {
    RegSize8 = 0,
    RegSize16 = 1,
    RegSize32 = 2,
    RegSize64 = 3,
}

pub use RegSignedness::*;
pub use RegSize::*;

pub fn sign_extend_and_truncate(size_class: u8, value: u64) -> i64 {
    let value_size = 1 << size_class;
    let shift_size = (8 - value_size) * 8;
    let truncated_value = value << shift_size;

    return (truncated_value as i64) >> shift_size;
}

pub fn truncate(size_class: u8, value: u64) -> u64 {
    dbg!(size_class);
    let value_size = 1 << size_class;
    let shift_size = (8 - value_size) * 8;
    let truncated_value = value << shift_size;

    return truncated_value >> shift_size;
}

pub trait Register: Sized + Copy {
    fn id(self) -> Option<u8>;

    fn size_class(self) -> u8 {
        return 3;
    }

    fn is_signed(self) -> bool {
        return false;
    }

    fn expect_id(self) -> Result<u8, IError> {
        if let Some(id) = self.id() {
            return Ok(id);
        }

        return Err(IError::new("internal error: Register had null ID"));
    }
}

pub const REGISTER_CALL_ID: u8 = 0;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(transparent)]
pub struct InReg(u8);

impl InReg {
    pub const NULL: Self = Self(0);

    pub fn new(size_class: RegSize, id: u8) -> Self {
        assert!(id < 32);

        let not_null = 1u8 << 7;
        let size_class = (size_class as u8) << 5;

        return Self(not_null | size_class | id);
    }
}

impl Register for InReg {
    fn size_class(self) -> u8 {
        return (self.0 & 127) >> 5;
    }

    fn id(self) -> Option<u8> {
        if self.0 == 0 {
            return None;
        }

        return Some(self.0 & 31u8);
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(transparent)]
pub struct In64Reg(u8);

impl In64Reg {
    pub const NULL: Self = Self(0);

    pub fn new(id: u8) -> Self {
        assert!(id < 32);

        let not_null = 1u8 << 7;

        return Self(not_null | id);
    }
}

impl Register for In64Reg {
    fn id(self) -> Option<u8> {
        if self.0 == 0 {
            return None;
        }

        return Some(self.0 & 31u8);
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(transparent)]
pub struct Out64Reg(u8);

impl Out64Reg {
    pub const NULL: Self = Self(0);

    pub fn new(id: u8) -> Self {
        assert!(id < 32);
        assert!(id != 0);

        return Self(id);
    }
}

impl Register for Out64Reg {
    fn id(self) -> Option<u8> {
        let id = self.0 & 31u8;
        if id == 0 {
            return None;
        }

        return Some(id);
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(transparent)]
pub struct OutReg(u8);

impl OutReg {
    pub fn null(signed: RegSignedness, size_class: RegSize) -> Self {
        let sign_bit = (signed as u8) << 7;
        let size_class = (size_class as u8) << 5;

        return Self(sign_bit | size_class);
    }

    pub fn new(signed: RegSignedness, size_class: RegSize, id: u8) -> Self {
        assert!(id < 32);
        assert!(id != 0);

        let sign_bit = (signed as u8) << 7;
        let size_class = (size_class as u8) << 5;

        return Self(sign_bit | size_class | id);
    }
}

impl Register for OutReg {
    fn is_signed(self) -> bool {
        return (self.0 & (1 << 7)) != 0;
    }

    fn size_class(self) -> u8 {
        return (self.0 & 127) >> 5;
    }

    fn id(self) -> Option<u8> {
        let id = self.0 & 31u8;
        if id == 0 {
            return None;
        }

        return Some(id);
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct StackSlot {
    pub id: u8,
    pub offset: u8,
}

impl StackSlot {
    pub const MEH: Self = Self {
        id: 255,
        offset: 255,
    };

    pub fn new(id: u8) -> Self {
        return Self { id, offset: 0 };
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct AllocLen {
    pub len: u8,
    pub power: u8,
}

impl AllocLen {
    pub fn new(input_len: u32) -> Self {
        let leading_zeros = input_len.leading_zeros() as u8;

        let power = (32 - leading_zeros).saturating_sub(8);

        if power as u32 <= input_len.trailing_zeros() {
            let len = (input_len >> power) as u8;

            let lossy = (len as u32) << power;
            debug_assert_eq!(lossy, input_len);

            return Self { len, power };
        }

        // we need to round up here, because this compression is used for allocation
        // lengths, where the output length must always be larger than the input length
        let rounded_input_len = (1u32 << power) + input_len;
        let leading_zeros = rounded_input_len.leading_zeros() as u8;
        let power = (32 - leading_zeros).saturating_sub(8);
        let len = (rounded_input_len >> power) as u8;

        let lossy = (len as u32) << power;
        debug_assert!(lossy >= input_len);

        return Self { len, power };
    }

    pub fn len(self) -> u32 {
        let len = (self.len as u32) << self.power;

        return len;
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
//          designing it well to start with
//      2.  This is a for-fun project, so go fuck yourself
//
// -    Registers are 64 bit, two's compliment. Register 0 is reserved for
//      function calls, and can only be written to by Call and Ret (can be read
//      by anybody)
//
// -    For register-output:
//      -   Highest bit controls sign extend (set bit -> sign extend)
//      -   Next 2 bits control size (00 = 8bit, 01 = 16bit, 10 = 32bit, 11 = 64 bit)
//          writing a 8/16/32 bit value means either zeroing or sign-extending
//          the high order bytes
//      -   Next 5 bits decide the register ID
//      -   register-output cannot be written to by anything except call and ret,
//          so using RET_ID as the id means that the id is null
//
// -    For register-pointer-input/register-64-input:
//      -   Input size is always 64 bits
//      -   Highest bit is set when the register is not null
//      -   Next 2 bits are dummy
//      -   Next 5 bits decide the register ID
//
// -    For register-input:
//      -   Highest bit is set when the register is not null
//      -   Next 2 bits control size (00 = 8bit, 01 = 16bit, 10 = 32bit, 11 = 64 bit)
//          always read from lower-order bits when size is less than 64 bits
//      -   Next 5 bits decide the register ID
//
// -    In cases where an opcode accepts a stack-slot and a register-output, if the
//      register ID is null, the opcode result should be stored in the stack,
//      and otherwise should be stored in the register. The size bits on the
//      register flags should be used to determine write size
//
// -    For stack-slot:
//      -   First byte is the stack id
//      -   second byte is the offset into that id
//
// -    stack-id is a stack id
//
// -    In opcodes with a len-power and len, they combine to produce a 32 bit value,
//      using compression style from interp/memory.rs
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[non_exhaustive]
#[repr(align(4))]
pub enum Opcode {
    Func, // opcode u8 u16

    // opcode u8-len-power u8-len u8-register-output
    StackAlloc {
        len: AllocLen,
        save_address: Out64Reg,
    },
    // opcode u8 u16-count
    StackDealloc {
        count: u16,
    },
    // opcode u8-register-output u8-register-64-input u8
    HeapAlloc {
        register_out: Out64Reg,
        register_64_in: In64Reg,
    },
    // opcode u8-register-64-input u16
    HeapDealloc {
        register_64_in: In64Reg,
    },

    // opcode u8-register-output u16-value
    Make16 {
        register_out: OutReg,
        value: u16,
    },
    // opcode u8-register-output u16-stack-slot u32-value
    Make32 {
        register_out: OutReg,
        stack_slot: u16,
    },
    // opcode u8-register-output u16-stack-slot u32-low-order-bits u32-high-order-bits
    Make64 {
        // This is Out64Reg because if you need sign-extension/truncation behavior,
        // you could've just used Make32 or Make16. Like if you're truncating
        // to 32 bits anyways, just truncate ahead of time, and use Make32.
        register_out: Out64Reg,
        stack_slot: StackSlot,
    },
    // opcode u8-register-output u16-stack-id
    MakeFp {
        register_out: Out64Reg,
        stack_id: u16,
    },

    // in-place
    // opcode u8-register-output u16-stack-slot
    Truncate {
        register_out: OutReg,
        stack_slot: u16,
    },
    // opcode u8-register-output u16-stack-slot
    // ignores sign extension
    BoolNorm {
        register_out: OutReg,
        stack_slot: u16,
    },
    // opcode u8-register-output u16-stack-slot
    // ignores sign extension
    BoolNot {
        register_out: OutReg,
        stack_slot: u16,
    },

    // This is specifically intended to be used for adding an offset to a frame
    // pointer created with MakeFp, reducing the number of registers and instructions
    // that need to be used to make a pointer to the stack.
    Add16 {
        register_out: Out64Reg,
        value: u16,
    },

    // opcode u8-register-output u8-register-pointer-input u8
    Get {
        register_out: OutReg,
        pointer: In64Reg,
    },
    // opcode u8-register-pointer-input u8-register-input u8
    Set {
        pointer: In64Reg,
        value: InReg,
    },

    // Register inputs are source, destination, length
    // opcode u8-register-pointer-input u8-register-pointer-input u8-register-64-input
    MemCopy {
        source: In64Reg,
        dest: In64Reg,
        byte_count: In64Reg,
    },

    // Wrapping Integer operations
    // register-output signed-ness determines both the sign-extension of inputs
    // into 64 bits and also the operation signed-ness
    // opcode u8-register-output u8-register-input u8-register-input
    Add {
        register_out: OutReg,
        left: InReg,
        right: InReg,
    },
    // opcode u8-register-output u8-register-input u8-register-input
    Sub {
        register_out: OutReg,
        left: InReg,
        right: InReg,
    },
    // opcode u8-register-output u8-register-input u8-register-input
    Mul {
        register_out: OutReg,
        left: InReg,
        right: InReg,
    },
    // opcode u8-register-output u8-register-input u8-register-input
    Div {
        register_out: OutReg,
        left: InReg,
        right: InReg,
    },
    // opcode u8-register-output u8-register-input u8-register-input
    Mod {
        register_out: OutReg,
        left: InReg,
        right: InReg,
    },

    // opcode u8-register-output u8-register-input u8-register-input
    RShift {
        register_out: OutReg,
        left: InReg,
        right: InReg,
    },
    // opcode u8-register-output u8-register-input u8-register-input
    LShift {
        register_out: OutReg,
        left: InReg,
        right: InReg,
    },

    // Ignores signedness
    // opcode u8-register-output u8-register-input u8-register-input
    BitAnd {
        register_out: OutReg,
        left: InReg,
        right: InReg,
    },
    // opcode u8-register-output u8-register-input u8-register-input
    BitOr {
        register_out: OutReg,
        left: InReg,
        right: InReg,
    },
    // opcode u8-register-output u8-register-input u8-register-input
    BitXor {
        register_out: OutReg,
        left: InReg,
        right: InReg,
    },
    // opcode u8-register-output u8-register-input u8-register-input
    BitNot {
        register_out: OutReg,
        left: InReg,
        right: InReg,
    },

    // Floating point
    // opcode u8-register-output u8-register-input u8-register-input
    FAdd {
        register_out: u8,
        left: InReg,
        right: InReg,
    },
    // opcode u8-register-output u8-register-input u8-register-input
    FSub {
        register_out: u8,
        left: InReg,
        right: InReg,
    },
    // opcode u8-register-output u8-register-input u8-register-input
    FMul {
        register_out: u8,
        left: InReg,
        right: InReg,
    },
    // opcode u8-register-output u8-register-input u8-register-input
    FDiv {
        register_out: u8,
        left: InReg,
        right: InReg,
    },
    // opcode u8-register-output u8-register-input u8-register-input
    FMod {
        register_out: u8,
        left: InReg,
        right: InReg,
    },

    // register-output size is implicitly ignored, because its not relevant here
    // register-output signed-ness determines both the sign-extension of inputs
    // into 64 bits and also the comparison signed-ness
    // opcode u8-register-output u8-register-input u8-register-input
    CompLt {
        register_out: OutReg,
        left: InReg,
        right: InReg,
    },
    // opcode u8-register-output u8-register-input u8-register-input
    CompLeq {
        register_out: OutReg,
        left: InReg,
        right: InReg,
    },
    // opcode u8-register-output u8-register-input u8-register-input
    CompEq {
        register_out: OutReg,
        left: InReg,
        right: InReg,
    },
    // opcode u8-register-output u8-register-input u8-register-input
    CompNeq {
        register_out: OutReg,
        left: InReg,
        right: InReg,
    },

    // The jumps here stays in the same allocation as they started in; the address
    // parameter only touches the offset part of the pointer
    // opcode u8 u16 u32-address
    Jump,
    // opcode u8-register-input u16-stack-slot u32-address
    JumpIfZero {
        register_in: u8,
        stack_slot: u16,
    },
    // opcode u8-register-input u16-stack-slot u32-address
    JumpIfNotZero {
        register_in: u8,
        stack_slot: u16,
    },

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
    // opcode u8-register-output u8-arg-count u8 u32-address
    Call {
        register_out: Out64Reg,
        arg_count: u8,
    },

    // Register inputs are interpreted differently depending on context
    // opcode u8-ecall-type u8-register-64-input u8-register-64-input
    Ecall {
        ecall_type: u8,
        input_1: In64Reg,
        input_2: In64Reg,
    },

    // Register inputs are string pointer and string length
    // opcode u8-skip-frames u8-register-pointer-input u8-register-64-input
    Throw {
        skip_frames: u8,
        message_ptr: In64Reg,
        message_len: In64Reg,
    },
}

impl From<u32> for Opcode {
    fn from(value: u32) -> Opcode {
        return unsafe { core::mem::transmute(value) };
    }
}

impl Into<u32> for Opcode {
    fn into(self) -> u32 {
        return unsafe { core::mem::transmute(self) };
    }
}

#[derive(Clone, Copy)]
#[repr(C)]
pub struct Ptr {
    pub offset: u32,

    // This is 1-indexed so that NULL = 0 is always invalid
    pub alloc_info_id: u32,
}

impl From<u64> for Ptr {
    fn from(value: u64) -> Ptr {
        return unsafe { core::mem::transmute(value) };
    }
}

impl Into<u64> for Ptr {
    fn into(self) -> u64 {
        return unsafe { core::mem::transmute(self) };
    }
}

// IDK why this is necessary, but before this struct was like 20 bytes, and now
// its 12. I thought using NonZeroU32 would make it better, but it did not.
// This is what we're using instead.
//                      - Albert Liu, Mar 12, 2022 Sat 22:47 EST
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum AllocInfo {
    StackLive {
        creation_op: u32,
        start: u32,
        len: AllocLen,
    },
    StackDead {
        creation_op: u32,
    },

    HeapLive {
        creation_op: u32,
        start: u32,
        len: AllocLen,
    },
    HeapDead {
        creation_op: u32,
        dealloc_op: u32,
    },

    // Executable, not read or writable
    StaticExe {
        start: u32,
        len: AllocLen,
    },

    Static {
        creation_expr: ExprId,
        start: u32,
        len: AllocLen,
    },
}

impl AllocInfo {
    pub fn get_range(self) -> Result<(u32, u32), IError> {
        use AllocInfo::*;

        #[rustfmt::skip]
        let (start, len) = match self {
            StackLive { start, len, .. }
            | HeapLive { start, len, .. }
            | StaticExe { start, len, }
            | Static { start, len, .. } => {
                (start, len.len())
            }

            StackDead { creation_op, } => {
                return Err(IError::new("stackdead"));
            }

            HeapDead { creation_op, dealloc_op, } => {
                return Err(IError::new("stackdead"));
            }
        };

        return Ok((start, len));
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BinaryManifest {
    // bounds of static exe allocation, use these to calculate program counter
    // and do bounds checking
    pub static_exe_start: u32,
    pub static_exe_end: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AllocTracker {
    // eventually, this should be garbage-collected; probably should just
    // be a custom GC, don't try to make something generic
    pub bytes: Pod<u8>,
    pub alloc_info: Pod<AllocInfo>,
    pub manifest: BinaryManifest,
}

impl AllocTracker {
    pub fn new() -> Self {
        // TODO Use manifest at alloc_index=0

        Self {
            bytes: Pod::new(),
            alloc_info: Pod::new(),
            manifest: BinaryManifest {
                static_exe_start: 0,
                static_exe_end: 0,
            },
        }
    }

    #[inline]
    pub fn read_op_at_index(&self, index: u32) -> u32 {
        let pointer = &self.bytes[index] as *const u8;

        let offset = pointer.align_offset(4);
        debug_assert_eq!(offset, 0);

        return unsafe { *(pointer as *const u32) };
    }

    // NOTE all alocations are aligned to 8 bytes
    pub fn alloc_range(&mut self, len: AllocLen) -> CopyRange<u32> {
        let start = self.bytes.len() as u32;

        let lossy_len = len.len();
        let lossy_len = (lossy_len - 1) / 8 * 8 + 8;
        self.bytes.reserve(lossy_len as usize);

        for _ in 0..lossy_len {
            self.bytes.push(0);
        }

        let range = r(start, start + lossy_len);

        #[cfg(debug_assertions)]
        {
            let ptr = &self.bytes[range.start] as *const u8;
            assert_eq!(ptr.align_offset(8), 0);
        }

        return range;
    }

    pub fn alloc_exe(&mut self, op_count: u32) -> &mut [u32] {
        use AllocInfo::*;

        let len = AllocLen::new(op_count * 4);
        let range = self.alloc_range(len);

        let info = StaticExe {
            start: range.start,
            len,
        };

        self.alloc_info.push(info);

        let bytes = &mut self.bytes[range];
        let pointer = bytes.as_mut_ptr() as *mut u32;

        debug_assert!(range.len() / 4 >= op_count);

        self.manifest.static_exe_start = range.start;
        self.manifest.static_exe_end = range.start + op_count * 4;

        return unsafe { core::slice::from_raw_parts_mut(pointer, op_count as usize) };
    }

    pub fn alloc_static(&mut self, len: u32, creation_expr: ExprId) -> (Ptr, u32) {
        use AllocInfo::*;

        let alloc_len = AllocLen::new(len);
        let range = self.alloc_range(alloc_len);
        let start = range.start;

        let info = StaticExe {
            start: range.start,
            len: alloc_len,
        };

        self.alloc_info.push(info);
        let alloc_info_id = self.alloc_info.len() as u32;

        let ptr = Ptr {
            offset: 0,
            alloc_info_id,
        };

        return (ptr, range.len());
    }

    pub fn alloc(&mut self, len: u32, creation_op: u32) -> (Ptr, u32) {
        use AllocInfo::*;

        let alloc_len = AllocLen::new(len);
        let range = self.alloc_range(alloc_len);
        let start = range.start;

        let info = HeapLive {
            creation_op,
            start,
            len: alloc_len,
        };

        self.alloc_info.push(info);

        let alloc_info_id = self.alloc_info.len() as u32;

        let ptr = Ptr {
            offset: 0,
            alloc_info_id,
        };

        return (ptr, range.len());
    }

    pub fn alloc_stack(&mut self, len: AllocLen, creation_op: u32) -> Ptr {
        use AllocInfo::*;

        let range = self.alloc_range(len);
        let start = range.start;

        let info = StackLive {
            creation_op,
            start,
            len,
        };

        self.alloc_info.push(info);

        let alloc_info_id = self.alloc_info.len() as u32;

        let ptr = Ptr {
            offset: 0,
            alloc_info_id,
        };

        return ptr;
    }

    pub fn dealloc_stack(&mut self, ptr: Ptr) -> Result<u32, IError> {
        use AllocInfo::*;

        let alloc_info = self.get_alloc_info_mut(ptr)?;
        match *alloc_info {
            StackLive {
                creation_op,
                start,
                len,
            } => {
                *alloc_info = StackDead { creation_op };

                return Ok(len.len());
            }

            _ => return Err(IError::new("internal error")),
        }
    }

    pub fn dealloc_heap(&mut self, ptr: Ptr, dealloc_op: u32) -> Result<u32, IError> {
        use AllocInfo::*;

        let alloc_info = self.get_alloc_info_mut(ptr)?;
        match *alloc_info {
            HeapLive {
                creation_op,
                start,
                len,
            } => {
                *alloc_info = HeapDead {
                    creation_op,
                    dealloc_op,
                };

                return Ok(len.len());
            }

            HeapDead {
                creation_op,
                dealloc_op,
            } => {
                return Err(IError::new(
                    "tried to free memory that has already been freed (aka double-free)",
                ));
            }

            _ => return Err(IError::new("tried to free memory that isn't on the heap")),
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

        let (start, alloc_len) = alloc_info.get_range()?;

        let ptr_end = ptr.offset + len;
        if ptr_end > alloc_len {
            return Err(IError::new("invalid pointer"));
        }

        return Ok(r(ptr.offset, ptr_end));
    }
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
            let compressed = AllocLen::new(input_len);

            assert_eq!(input_len, compressed.len());
        }
    }

    #[test]
    fn test_alloc_len_compression_lossy() {
        let tests: &[(u32, u32)] = &[
            ((254 << 20) + 1, 255 << 20),
            ((254 << 20) + 1, 255 << 20),
            ((254 << 21) + 1, 255 << 21),
            ((254 << 22) + 1, 255 << 22),
            ((254 << 23) + 1, 255 << 23),
            ((254 << 23) + (1 << 22), 255 << 23),
            ((255 << 20) + 1, 256 << 20),
            ((255 << 20) + (1 << 11), 256 << 20),
        ];

        let mut i = 0;
        for &(input_len, expected_len) in tests {
            let compressed = AllocLen::new(input_len);

            assert_eq!(expected_len, compressed.len(), "index: {}", i);

            i += 1;
        }
    }

    #[test]
    fn test_alloc_alignment() {
        let mut data = AllocTracker::new();
        for i in 0..100 {
            data.alloc_range(AllocLen::new(13));
        }
    }

    #[test]
    fn type_sizing() {
        assert_eq!(mem::size_of::<AllocInfo>(), 12);
        assert_eq!(mem::size_of::<ExprId>(), 4);
        assert_eq!(mem::size_of::<Opcode>(), 4);
        assert_eq!(mem::align_of::<Opcode>(), 4);
    }
}
