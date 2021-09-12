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

Project dependencies are in `.gone-deps`. Files passed to compiler run in order
that they are passed; folders run `init.gme` first, then the rest is decided by
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
