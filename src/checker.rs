use crate::util::*;
use crate::*;
use std::collections::hash_map::HashMap;

#[derive(Debug, PartialEq, Clone, Copy)]
pub enum Type {
    // Means that the expression that returns this value doesn't ever return
    // a value directly (early return, loop forever, crash, ...)
    Never,

    // Void in C
    Null,

    Unsigned,
    String,

    Procedure,
}

pub fn check_ast(ast: &Ast) -> Result<TypeEnv, Error> {
    let mut types = TypeEnv {
        type_of: HashMap::new(),
        ident_to_expr: HashMap::new(),
    };

    let mut scope = ScopeEnv {
        vars: HashMap::new(),
        kind: ScopeKind::Global,
    };

    let mut env = CheckEnv {
        types: &mut types,
        scope,
    };

    for expr in ast.block.stmts {
        env.check_expr(expr)?;
    }

    return Ok(types);
}

pub struct TypeEnv {
    pub type_of: HashMap<ExprId, Type>,
    pub ident_to_expr: HashMap<ExprId, ExprId>,
}

struct CheckEnv<'a> {
    types: &'a mut TypeEnv,
    scope: ScopeEnv<'a>,
}

impl<'a> CheckEnv<'a> {
    fn chain_local<'b>(&'b mut self) -> CheckEnv<'b> {
        return CheckEnv {
            types: self.types,
            scope: ScopeEnv {
                kind: ScopeKind::Local {
                    parent: &mut self.scope,
                },
                vars: HashMap::new(),
            },
        };
    }

    fn chain_proc<'b>(&'b mut self) -> CheckEnv<'b> {
        return CheckEnv {
            types: self.types,
            scope: ScopeEnv {
                kind: ScopeKind::Procedure {
                    parent: &mut self.scope,
                },
                vars: HashMap::new(),
            },
        };
    }

    fn check_block(&mut self, block: &Block) -> Result<Type, Error> {
        use ExprKind::*;

        for expr in block.stmts {
            let p = match *expr {
                Procedure(p) => p,
                _ => continue,
            };
        }

        for expr in block.stmts {
            self.check_expr(expr)?;
        }

        let ty = Type::Null;
        return Ok(ty);
    }

    fn check_expr(&mut self, id: ExprId) -> Result<Type, Error> {
        use ExprKind::*;

        let expr = &*id;
        let mut ty;

        match *expr {
            Procedure(p) => {
                let mut proc_child = self.chain_proc();

                let result = proc_child.check_expr(p.code)?;

                ty = Type::Null;
            }

            Integer(value) => {
                ty = Type::Unsigned;
            }

            Let { symbol, value } => {
                let result = self.check_expr(value)?;

                if let Some(prev) = self.scope.vars.insert(symbol, value) {
                    return Err(Error::new("redeclared variable", id.loc()));
                }

                ty = Type::Null;
            }

            Ident { symbol } => {
                let value = match self.scope.search(symbol) {
                    Some(e) => e,
                    None => {
                        return Err(Error::new("couldn't find variable", id.loc()));
                    }
                };

                self.types.ident_to_expr.insert(id, value);

                ty = self.types.type_of[&value];
            }

            BinaryOp { kind, left, right } => {
                let left_ty = self.check_expr(left)?;
                let right_ty = self.check_expr(right)?;

                if left_ty != right_ty {
                    return Err(Error::new(
                        "binary operation should be on values of similar type",
                        id.loc(),
                    ));
                }

                ty = left_ty;
            }

            Block(block) => {
                let mut child = self.chain_local();

                for expr in block.stmts {
                    child.check_expr(expr)?;
                }

                ty = Type::Null;
            }

            Call { callee, args } => {
                const PRINT: u32 = Key::Print as u32;

                match *callee {
                    Ident { symbol: PRINT } => {}

                    _ => {
                        unimplemented!("function calls besides print aren't implemented");
                    }
                }

                for arg in args {
                    self.check_expr(arg)?;
                }

                ty = Type::Null;
            }

            k => unimplemented!("{}", k.name()),
        }

        if let Some(_) = self.types.type_of.insert(id, ty) {
            panic!("idk");
        }

        return Ok(ty);
    }
}

enum ScopeKind<'a> {
    Global,
    Procedure { parent: &'a ScopeEnv<'a> },
    Local { parent: &'a ScopeEnv<'a> },
}

// eventually this will be chaining
struct ScopeEnv<'a> {
    kind: ScopeKind<'a>,
    vars: HashMap<u32, ExprId>,
}

impl<'a> ScopeEnv<'a> {
    fn parent(&self) -> Option<&ScopeEnv<'a>> {
        return match self.kind {
            ScopeKind::Global => None,
            ScopeKind::Procedure { parent } => Some(parent),
            ScopeKind::Local { parent } => Some(parent),
        };
    }

    fn search(&self, symbol: u32) -> Option<ExprId> {
        let mut current = self;

        loop {
            if let Some(e) = current.vars.get(&symbol) {
                return Some(*e);
            }

            if let Some(parent) = current.parent() {
                current = parent;

                continue;
            }

            return None;
        }
    }
}
