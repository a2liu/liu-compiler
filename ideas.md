all scopes have same semantics, which are that compile-time constants get hoisted
to top of scope and everyting else executes sequentially.

```
f :: func(a,b,c : int; d := "") string {
  return "hello"
}

f(12, 13, 14)
f(a = 12, c = 14, b = 13)

b := a + 13 // compile error, name not found
a := 12
```

Enum keyword does the normal enum generation but with some namespace
manipulation as well

```
enum Worker {
  Intern
  FullTime
  Manager {
    reports: &Worker
  }
}
```

creates the `Worker` type as well as `Worker.Intern`, `Worker.FullTime`, and
`Worker.Manager`. `Worker` is defined as
`Worker.Intern | Worker.FullTime | Worker.Manager`.

Project dependencies are in `.liu-deps`. Files passed to compiler run in order
that they are passed; folders run `init.liu` first, then the rest is decided by
import order.

Casting an anonymous struct to a named struct type causes the type's constructor
to run, thus fully creating the type.

`self` identifier needs to be special, because it allows referencing the current
object in the constructor, as well as makes it a lil more terse to create member
methods.

Keyword arguments are defined by taking in an argument called keyword_args (which must be a struct).
Keyword arguments assign to fields in that argument.

Typechecking doesn't do opcode generation (unless it makes sense later but right
now probably not).

Scopes don't do the thing where they automatically become structs or whatever.
That'll probably be a thing with modules, but that's it.

Sidestep the whole "prefix vs infix operator" thing by just having a `:` after control
flow. Like in Python.

scopes contain information about polymorphic type variables, which get pushed onto
the typechecker during checking. Or something, idk.

### Big Ideas (Compiler/Language)
- Small target set (maybe native + bytecode?)
- bytecode debugger
- Compiler internals are exposed to language
- Definitely want a `#metaprogram` directive.
- Context struct
- Jai-like macros
- Notes are either identifiers or `@(expr)`, where `expr` is an expression evaluated
  in the note's scope at compile time.

### Big Ideas (Libraries)
The following extensions to the language hopefully can be done in the language itself:

- calling convention stuff (? requires use-defined codegen)
- Python module as a target (? requires user-defined codegen)
- User-defined directives, defined in metaprogram before build starts (? might be hard to implement)
- Stack frame stuff (? might need built-in parts)
- Interfaces (? maybe better to keep in the language itself)
- Pass utilies for writing compiler passes
- Program visualization stuff
- Serialization standard library stuff
- Dynamic dispatch
- Inheritance
- Debugger + Debugging utils
- Testing utils, test auto generators
- Code transformations
- Smart code diffing

### Small Ideas (Compiler/Language)
- `require` and `prevent` that are like `if` except their block requires you to return,
  and has no `else`. `require` enters the block if the condition is false, `prevent` enters
  if the condition is true.
- Definitely want a way to insert code directly into enclosing block from a macro.
- Owning pointer in the type system.
- Allow notes in strategic places, so that people can implement interesting stuff if they want.
- Make compiler restructure data to allow for weird padding stuff. Assignment of
  data never overwrites padding.
- Overload dot operator like Swift, so it calls a function and passes the member
  name as a string.
- The swift closure thing. Haven't decided if it will actually be a closure, or
  just like a code block, but it does seem like it'd be nice to have.

  ```
  a.b() {
    print(it);
  }
  ```

- iterator methods are just for_expansions from jai but without having to make a
  custom type or go through iterator resolution
- Maybe just say that `a = 12` declares if the variable doesn't exist (in any scope),
  and assigns otherwise. The `a : s64 = 12` form always declares. Compile-time variables
  still need to be declared with `a :: 12`
- Inheritance field can be manually specified, and structs can be abstract if you want
- First-class bitfield type
- Compile-time values that contain pointers should probably be unusable from runtime
  code
- No lazy typechecking in the compiler.
- `for_now` that lets you assign to something until the end of the scope. Syntax
  is `for_now a.b.c = 12` and semantics are:

  ```
  previous := a.b.c;
  a.b.c = 12;
  defer a.b.c = previous;
  ```
- Assignment overloading might be nice, but we probably shouldn't allow overloading
  of assigning a value of type `A` to a target of type `A`. If left and right are
  the same, it's a normal assignment, with normal semantics. Or maybe overloading
  the assignemnt operator for `A` to `A` gives the type move semantics? At the
  very least we don't want the whole C++ copy-constructor move-constructor nonsense.
- Three reference types, pointer, array_view, and reference. Reference and array_view
  are nonnullable, pointer is not. Pointer allows addition and dereference (but no subscript),
  array_view allows subscript, reference allows dereference.
- Fun closure thing for control flow statements as well (except it's not really a closure
  in those cases)

  ```
  if a.b() |err| {
    print(err);
  }

  while a.b() |err| {
    print(err);
  }

  for a.b() |it| {
  }
  ```
- `a : int;` can create a `DefaultExpr` AST node so that there's one less case of
  the value slot being null. In fact, parameter declararations can create `ParameterExpr`
  instread of `DefaultExpr`. Doing so simplifies typechecking a bit, and means
  another field will never be null
