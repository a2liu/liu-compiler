# Ideas

Simple language, with simple user-facing semantics.

Compiler is exposed as library, and can by imported in the build script to
accomplish much more complex stuffs. Default mode is to interpret the given
file, so that this stuff is easier to do.

Make compiler nice to work with as a library, so we can run experiments on what
kinds of patterns are helpful and what arent.

## Eventual Goals
1.  Easy to develop on for those familiar with C semantics
2.  Easy to write scripts to automate the simple things
3.  Possible to optimize memory access patterns easily
4.  Possible to output human-readable code in another, more
    production-friendly language

## Include in base language
- Primitives, pointers, slices
- Functions
- Control flow
- Type id's, runtime type information
- Dynamic memory
- Iterators (as macros? or as generators that behave like macros?)
- Scope begin/end directives, scoped feature enable/disable
- Simple compile-time constants (i.e. literals)
- Structs structs
- C ABI
- Simple enums
- Basic type inference
- Function pointers
- Allocators
- Implicit context
- defer, named continue/break
- Some kind of "throw error" thing, but not using stack unwinding
- Nullable checks: `a ?? b`, `a?.b`, `a?(`, `a?[`, etc.
- Some kind of "pass up this if it throws" thing, i.e. `could_error()!`

## IDK Yet
- Macros
- Generics
- Closures
- Complex enums
- Non-nullable types
- Overloading
- Operator overloading
- Interfaces/traits/etc.
- Anonymous structs
- Contracts/type requirements
- Compile-time constant evaluation
- Tuples
- async-await
- Modify AST
- Custom typechecking
- Inheritance using explicit type field? Call it closed and it can become an enum?

## Too Complex, use compiler API
- Python ABI
- Correctness checking
- Generate fuzzers, test harnesses
- Insert source code as string or nodes

## Too Complex, you're on your own
- Inheritance
- Garbage collection
- RAII


## Intended Architecture

AST memory layout:
-   Since location information is not accessed during most of compilation,
    AST is laid out with structure in one arena and locations in the other.
-   parser threads ask for large ranges; data in these ranges are locked to the
    file being parsed
-   File markers are not necessary on every location, so attach them to the
    range
-   Use 32-bit IDs instead of references. If it really comes to it, we can parse
    while concurrently typechecking to free up more ID space, but it seems unnecessary.

Bytecode memory layout:
-   Global garbage collector manages basic block lifetimes/allocations
-   Once data is written it's read-only, rewriters write new basic blocks and
    write to a global ID table
-   ID table can maaaaybe be pre-allocated? idk

### NOTE: NONE OF THIS IS IMPLEMENTED

lexing/parsing -> one global lexer thread, X parser threads

1.  global thread lexes input
2.  sends relevant data off to a parser thread
    1. parser sends full AST data to global type checker thread when finished
    2. parser sends additional file paths to lexer

3.  goto 1


checking -> one global type database/thread, AST checking done by multiple threads

1.  wait on AST
2.  Get types from the AST and store in global database

    NOTE: Can this be done concurrently? Is there a reason to or not to?

3.  once all types are available, start up type checking threads


Write job system + allocator
Use the idea of Cancellation Token to allow for task cancellation

