# Compiler
Compiler written in Rust. Gonna build a simple thing first, then try to make it
good over time.

### Stuff I found helpful
- LLVM
  - Godbolt with x86-64 clang, `-g0 -O1`, and IR viewer (shows LLVM IR in text form)
  - Online LLVM resources haven't been helpful so far for more abstract concepts.
    Once you have a concrete problem or want to know what functions to call, the docs
    might help, but in general the resources online have not been helpful so far.
    Godbolt is usually much faster and more reliable.
- Register allocation -
  http://www.cse.iitm.ac.in/~krishna/courses/2017/even-cs6013/linearscan.pdf

# Ideas

Simple language, with simple user-facing semantics.

Compiler is exposed as library, and can by imported in the build script to
accomplish much more complex stuffs. Default mode is to interpret the given
file, so that this stuff is easier to do.

Make compiler nice to work with as a library, so we can run experiments on what
kinds of patterns are helpful and what arent.

Can also add this compiler as library to TCI lol, and have TCI target this as
its backend.

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
- Default hard-crash for error types?
- Memory layouts that don't encode types themselves, but get typechecked, e.g.

  ```
  layout a {
  }

  type b layout a
  ```

- `proc a = b`, to prevent unnecessary duplication of code in the binary/optimization
  phase, and weird inlining stuffs
  - `proc a(a, b) = b(b, a, 12)` doesn't require inlining during codegen, and
    can be inlined immediately

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
- Ability to take same memory and have it behave in different ways without a
  bunch of different boilerplate stuff. Like, i want to take the same memory
  layout, and do a different thing on it depending on some compile-time constraints.
  I want to be sure that the type doesn't cause generation of a bunch of unnecessary
  code, but that the compile-time constraints are kept constant.
- Try to keep base language to only things that affect runtime semantics,
  correctness typechecking checking can be done with metaprogramming

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
### NOTE: NONE OF THIS IS IMPLEMENTED


`GraphOp` memory layout v1:
-   Global allocator bump allocates graph
-   Graph blocks are static, and just reference each other + functions directly

`GraphOp` memory layout v2:
-   Global garbage collector manages basic block lifetimes/allocations
-   Once data is written it's read-only, optimization passes write new basic blocks
    and write to a global ID table
-   passes take mutation mutex on functions, do their stuff, then re-add
    function with new blocks back to database
-   How does inlining work? Inlining requires reading the function, so I guess
    it requires the mutex? I guess we want the data from the inline to be closer
    to optimal
-   GC also takes mutation mutex to do moving GC in the global ring buffer
-   Make MPSC queue for GC references, so they can be moved as needed
-   Write some kind of parking lot thing to work with tasks
-   Mutexes can't really be moved while locked, so... what do?

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
Use the idea of Cancellation Token to allow for task cancellation?

