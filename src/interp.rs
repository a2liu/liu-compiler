use crate::util::*;
use crate::*;
use core::fmt::Write;
use std::collections::hash_map::HashMap;

pub fn interpret(ast: &Ast, env: &TypeEnv, stdout: &mut dyn Write) {
    let mut stack = BucketList::new();

    let mut interp = Interp { env, stdout };

    let mut values = HashMap::new();

    let scope = Scope {
        values: &mut values,
        alloc: stack.scoped(),
    };

    interp.block(scope, &ast.block);
}

struct Interp<'a> {
    env: &'a TypeEnv,
    stdout: &'a mut dyn Write,
}

impl<'a> Interp<'a> {
    fn block(&mut self, mut scope: Scope, block: &Block) {
        for expr in block.stmts {
            self.expr(&mut scope, expr);
        }
    }

    fn expr(&mut self, scope: &mut Scope, id: ExprId) -> Register {
        use ExprKind::*;

        let e = &*id;

        match *e {
            Integer(value) => {
                return Register::from_u64(value);
            }

            Ident { .. } => {
                let expr = unwrap(self.env.ident_to_expr.get(&id));
                let register = unwrap(scope.values.get(expr));

                return *register;
            }

            Let { value, .. } => {
                let expr = value;
                let value = self.expr(scope, expr);

                scope.values.insert(expr, value);

                return ZERO;
            }

            Block(block) => {
                self.block(scope.chain(), &block);

                return ZERO;
            }

            Call { callee, args } => {
                let mut add_space = false;

                for arg in args {
                    let value = self.expr(scope, arg);
                    if add_space {
                        expect(write!(self.stdout, " "));
                    }

                    expect(write!(self.stdout, "{}", value.to_u64()));
                    add_space = true;
                }

                expect(write!(self.stdout, "\n"));

                return ZERO;
            }

            BinaryOp { kind, left, right } => {
                use BinaryExprKind::*;

                let left = self.expr(scope, left);
                let right = self.expr(scope, right);

                let value = match kind {
                    Add => left.to_u64().wrapping_add(right.to_u64()),

                    _ => 0u64,
                };

                return Register::from_u64(value);
            }

            e => unimplemented!("{:?}", e),
        }
    }
}

struct Scope<'a> {
    values: &'a mut HashMap<ExprId, Register>,
    alloc: ScopedBump<'a>,
}

impl<'a> Scope<'a> {
    fn chain<'b>(&'b mut self) -> Scope<'b> {
        return Scope {
            values: self.values,
            alloc: self.alloc.chain(),
        };
    }
}

const ZERO: Register = Register { value: 0 };

#[derive(Clone, Copy)]
#[repr(transparent)]
struct Register {
    value: u64,
}

impl Register {
    fn from_u64(value: u64) -> Self {
        return Self { value };
    }

    fn to_u32(self) -> u32 {
        return self.value as u32;
    }

    fn to_u64(self) -> u64 {
        return self.value;
    }
}
