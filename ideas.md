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
- `guard` and `check` that are like `if` except their block requires you to return,
  and has no `else`. `guard` enters the block if the condition is false, `check` enters
  if the condition is true.
- Definitely want a way to insert code directly into enclosing block from a macro.
- Owning pointer in the type system.
- Allow notes in strategic places, so that people can implement interesting stuff if they want.
- Make compiler restructure data to allow for weird padding stuff.
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

