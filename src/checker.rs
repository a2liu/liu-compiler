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

    U64,
    String,

    Procedure,
}

#[derive(Debug, Clone, Copy)]
pub struct Value {
    pub op: u32,
    pub ty: Type,
}

impl Value {
    pub fn new(op: u32, ty: Type) -> Value {
        return Value { op, ty };
    }
}

const NULL: Value = Value {
    op: u32::MAX,
    ty: Type::Null,
};

pub fn check_ast(ast: &Ast) -> Result<(Graph, u32), Error> {
    let mut types = TypeEnv {};

    let mut scope = ScopeEnv {
        vars: HashMap::new(),
        kind: ScopeKind::Global {
            next_variable_id: Cell::new(0),
        },
    };

    let mut graph = Graph::new();
    let entry = graph.get_block_id();

    let mut append = GraphAppend {
        block_id: entry,
        ops: Pod::new(),

        // Making this start at 1 makes register allocation easier, and doesn't have
        // any real ramifications long term.
        //                              - Albert Liu, Mar 21, 2022 Mon 01:21 EDT
        op_id: 1,
    };

    let mut env = CheckEnv {
        types: &mut types,
        graph: &mut graph,
        append: &mut append,
        scope,
    };

    for expr in ast.block.stmts {
        env.check_expr(expr)?;
    }

    let mut ops = append.ops;
    let last = append.block_id;

    ops.push(GraphOp::Loc(ExprId::NULL));
    ops.push(GraphOp::ExitSuccess);

    graph.write_block(last, ops);

    return Ok((graph, entry));
}

pub struct TypeEnv {}

struct GraphAppend {
    block_id: u32,
    op_id: u32,
    ops: Pod<GraphOp>,
}

struct CheckEnv<'a> {
    types: &'a mut TypeEnv,
    graph: &'a mut Graph,
    append: &'a mut GraphAppend,
    scope: ScopeEnv<'a>,
}

impl<'a> CheckEnv<'a> {
    fn chain_local<'b>(&'b mut self) -> CheckEnv<'b> {
        return CheckEnv {
            types: self.types,
            graph: self.graph,
            append: self.append,
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
            append: self.append,
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

            unimplemented!("procedures aren't implemented yet");
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
                self.append.ops.push(GraphOp::Loc(id));

                let op = self.append.op_id;
                self.append.op_id += 1;

                self.append.ops.push(GraphOp::ConstantU64 {
                    output_id: op,
                    value,
                });

                return Ok(Value::new(op, Type::U64));
            }

            Let { symbol, value } => {
                let result = self.check_expr(value)?;

                let stack_id = self.scope.declare(id, symbol, result.ty)?;

                self.append.ops.push(GraphOp::Loc(id));
                self.append.ops.push(GraphOp::StackVar { size: 8 });
                self.append.ops.push(GraphOp::StoreStack64 {
                    stack_id,
                    offset: 0,
                    input_id: result.op,
                });

                return Ok(NULL);
            }

            Ident { symbol } => {
                let var_info = match self.scope.search(symbol) {
                    Some(e) => e,
                    None => {
                        return Err(Error::new("couldn't find variable", id.loc()));
                    }
                };

                let op = self.append.op_id;
                self.append.op_id += 1;

                self.append.ops.push(GraphOp::Loc(id));
                self.append.ops.push(GraphOp::LoadStack64 {
                    output_id: op,
                    stack_id: var_info.id,
                    offset: 0,
                });

                return Ok(Value::new(op, var_info.ty));
            }

            If { cond, if_true } => {
                let end_block = self.graph.get_block_id();

                // let value = self.check_arms(end_block, &[if_true])?;

                // assert_eq!(self.graph.ops.len(), 0);
                // let ops = core::mem::replace(&mut self.graph.ops, Pod::new());
                // self.graph.graph.write_block(self.graph.block_id, ops);
                // self.graph.block_id = end_block;

                // return Ok(value);
                return Ok(NULL);
            }

            IfElse {
                cond,
                if_true,
                if_false,
            } => {
                let end_block = self.graph.get_block_id();

                // let value = self.check_arms(end_block, &[if_true, if_false])?;

                // assert_eq!(self.graph.ops.len(), 0);
                // let ops = core::mem::replace(&mut self.graph.ops, Pod::new());
                // self.graph.graph.write_block(self.graph.block_id, ops);
                // self.graph.block_id = end_block;

                return Ok(NULL);
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

                let op = self.append.op_id;
                self.append.op_id += 1;

                self.append.ops.push(GraphOp::Loc(id));
                self.append.ops.push(GraphOp::Add64 {
                    out: op,
                    op1: left_value.op,
                    op2: right_value.op,
                });

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

                    self.append.ops.push(GraphOp::Loc(id));
                    self.append.ops.push(GraphOp::BuiltinPrint { op: value.op });
                }

                self.append.ops.push(GraphOp::Loc(id));
                self.append.ops.push(GraphOp::BuiltinNewline);

                return Ok(NULL);
            }

            k => unimplemented!("{}", k.name()),
        }
    }

    // Completes the current block properly, and also completes all the blocks
    // it produces by having them jump to the exit block
    fn check_arms(&mut self, exit_block: u32, arms: &[Arm]) -> Result<Value, Error> {
        let parent = self.append.block_id;

        let mut pod = Pod::new();

        pod.push(1);

        return Ok(NULL);
    }
}

struct Arm {
    block_id: u32,
    expr: ExprId,
}

enum ScopeKind<'a> {
    Global {
        next_variable_id: Cell<u16>,
    },
    Procedure {
        parent: &'a ScopeEnv<'a>,
        next_variable_id: Cell<u16>,
    },
    Local {
        parent: &'a ScopeEnv<'a>,
    },
}

#[derive(Clone, Copy)]
struct VariableInfo {
    id: u16,
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

    fn declare(&mut self, id: ExprId, symbol: u32, ty: Type) -> Result<u16, Error> {
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
