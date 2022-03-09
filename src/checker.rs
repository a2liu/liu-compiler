use crate::util::*;
use crate::*;
use core::cell::Cell;
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

#[derive(Debug, Clone, Copy)]
pub struct Value {
    pub op: Operand,
    pub ty: Type,
}

impl Value {
    pub fn new(op: Operand, ty: Type) -> Value {
        return Value { op, ty };
    }
}

const NULL: Value = Value {
    op: Operand::ConstantU64 { value: 0 },
    ty: Type::Null,
};

pub fn check_ast(ast: &Ast) -> Result<TypeEnv, Error> {
    let mut types = TypeEnv {};

    let mut scope = ScopeEnv {
        vars: HashMap::new(),
        kind: ScopeKind::Global {
            next_variable_id: Cell::new(0),
        },
    };

    let mut graph = Graph::new();

    let mut env = CheckEnv {
        types: &mut types,
        graph: &mut graph,
        scope,
    };

    for expr in ast.block.stmts {
        env.check_expr(expr)?;
    }

    return Ok(types);
}

pub struct TypeEnv {}

struct CheckEnv<'a> {
    types: &'a mut TypeEnv,
    graph: &'a mut Graph,
    scope: ScopeEnv<'a>,
}

impl<'a> CheckEnv<'a> {
    fn chain_local<'b>(&'b mut self) -> CheckEnv<'b> {
        return CheckEnv {
            types: self.types,
            graph: self.graph,
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
            graph: self.graph,
            scope: ScopeEnv {
                kind: ScopeKind::Procedure {
                    parent: &mut self.scope,
                    next_variable_id: Cell::new(0),
                },
                vars: HashMap::new(),
            },
        };
    }

    fn check_block(&mut self, block: &Block) -> Result<Value, Error> {
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

        return Ok(NULL);
    }

    fn check_expr(&mut self, id: ExprId) -> Result<Value, Error> {
        use ExprKind::*;

        let expr = &*id;

        match *expr {
            Procedure(p) => {
                let mut proc_child = self.chain_proc();

                let result = proc_child.check_expr(p.code)?;

                return Ok(NULL);
            }

            Integer(value) => {
                return Ok(Value::new(Operand::ConstantU64 { value }, Type::Unsigned));
            }

            Let { symbol, value } => {
                let result = self.check_expr(value)?;

                let id = self.scope.declare(id, symbol, result.ty)?;

                self.graph.add(
                    OpKind::Store64 {
                        pointer: Operand::ReferenceToStackLocal { id, offset: 0 },
                        value: result.op,
                    },
                    value,
                );

                return Ok(NULL);
            }

            Ident { symbol } => {
                let var_info = match self.scope.search(symbol) {
                    Some(e) => e,
                    None => {
                        return Err(Error::new("couldn't find variable", id.loc()));
                    }
                };

                let op = self.graph.add(
                    OpKind::Load64 {
                        pointer: Operand::ReferenceToStackLocal {
                            id: var_info.id,
                            offset: 0,
                        },
                    },
                    id,
                );

                return Ok(Value::new(op, var_info.ty));
            }

            BinaryOp { kind, left, right } => {
                let left_value = self.check_expr(left)?;
                let right_value = self.check_expr(right)?;

                if left_value.ty != right_value.ty {
                    return Err(Error::new(
                        "binary operation should be on values of similar type",
                        id.loc(),
                    ));
                }

                let op = self.graph.add(
                    OpKind::Add64 {
                        op1: left_value.op,
                        op2: right_value.op,
                    },
                    id,
                );

                return Ok(Value::new(op, left_value.ty));
            }

            Block(block) => {
                let mut child = self.chain_local();

                for expr in block.stmts {
                    child.check_expr(expr)?;
                }

                return Ok(NULL);
            }

            Call { callee, args } => {
                const PRINT: u32 = Key::Print as u32;

                match *callee {
                    Ident { symbol: PRINT } => {}

                    _ => {
                        return Err(Error::new(
                            "function calls besides print aren't implemented",
                            callee.loc(),
                        ));
                    }
                }

                for arg in args {
                    let value = self.check_expr(arg)?;

                    self.graph.add(OpKind::BuiltinPrint { op: value.op }, arg);
                }

                self.graph.add(OpKind::BuiltinNewline, id);

                return Ok(NULL);
            }

            k => unimplemented!("{}", k.name()),
        }
    }
}

enum ScopeKind<'a> {
    Global {
        next_variable_id: Cell<u32>,
    },
    Procedure {
        parent: &'a ScopeEnv<'a>,
        next_variable_id: Cell<u32>,
    },
    Local {
        parent: &'a ScopeEnv<'a>,
    },
}

#[derive(Clone, Copy)]
struct VariableInfo {
    id: u32,
    ty: Type,
}

// eventually this will be chaining
struct ScopeEnv<'a> {
    kind: ScopeKind<'a>,
    vars: HashMap<u32, VariableInfo>,
}

impl<'a> ScopeEnv<'a> {
    fn parent(&self) -> Option<&ScopeEnv<'a>> {
        return match self.kind {
            ScopeKind::Global { .. } => None,
            ScopeKind::Procedure { parent, .. } => Some(parent),
            ScopeKind::Local { parent } => Some(parent),
        };
    }

    fn search(&self, symbol: u32) -> Option<VariableInfo> {
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

    fn declare(&mut self, id: ExprId, symbol: u32, ty: Type) -> Result<u32, Error> {
        use std::collections::hash_map::Entry;

        let e = match self.vars.entry(symbol) {
            Entry::Vacant(v) => v,
            Entry::Occupied(o) => {
                return Err(Error::new("redeclared variable", id.loc()));
            }
        };

        let mut current = &self.kind;

        loop {
            let next = match current {
                ScopeKind::Local { parent } => {
                    current = &parent.kind;
                    continue;
                }

                ScopeKind::Procedure {
                    next_variable_id, ..
                } => next_variable_id,

                ScopeKind::Global { next_variable_id } => next_variable_id,
            };

            let id = next.get();
            next.set(id + 1);

            e.insert(VariableInfo { id, ty });

            return Ok(id);
        }
    }
}
