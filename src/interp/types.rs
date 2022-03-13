use crate::util::*;
use core::{fmt, mem};

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
//          always read from lower-order bits when possible
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

    // register-output sign extension and size are implicitly ignored, because
    // they're not relevant here
    CompLt,  // opcode u8-register-output u8-register-input u8-register-input
    CompLeq, // opcode u8-register-output u8-register-input u8-register-input
    CompEq,  // opcode u8-register-output u8-register-input u8-register-input
    CompNeq, // opcode u8-register-output u8-register-input u8-register-input

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
    Call, // opcode u8-register-output u8-arg-count u8 u32-address

    // Register inputs are interpreted differently depending on context
    Ecall, // opcode u8-ecall-type u8-register-64-input u8-register-64-input

    // Register inputs are string pointer and string length
    Throw, // opcode u8-skip-frames u8-register-input u8-register-64-input
}
