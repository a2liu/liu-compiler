use crate::*;
use core::cell::Cell;
use std::collections::hash_map::HashMap;

// Bruh wtf do i do
//
// Block stack-ly resets register numbers after every statement

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

#[derive(Debug, Clone, Copy)]
pub enum ValueSlot {
    StackLocation { id: u16 },
    ValuePointer { id: u16 },
    SaveSomewhere,
    Delete,
}

#[derive(Debug, Clone, Copy)]
pub enum ValueLocation {
    StackLocation { id: u16, offset: u32 },
    ValuePointer { id: u16 },

    StackSlot { id: u16 },
    Primitive { id: u16 },
    Written,
    NoValue,
}

const NULL: Value = Value {
    op: Operand::Null,
    ty: Type::Null,
};

pub fn check_ast(ast: &Ast) -> Result<(Graph, u32), Error> {
    let mut types = TypeEnv {};

    let mut scope = ScopeEnv {
        vars: HashMap::new(),
        kind: ScopeKind::Global {},
    };

    let mut graph = Graph::new();
    let mut ids = IdTracker::new();
    let entry = graph.get_block_id();

    let mut append = GraphAppend {
        block_id: entry,
        ops: Pod::new(),
    };

    let mut env = CheckEnv {
        types: &mut types,
        graph: &mut graph,
        ids: &mut ids,
        append: &mut append,
        scope,
    };

    for expr in ast.block.stmts {
        env.check_expr(ValueSlot::Delete, expr)?;
    }

    core::mem::drop(env);

    let mut ops = append.ops;
    let last = append.block_id;

    let op = GraphOp::new(GraphOpKind::ExitSuccess, Type::Null, ExprId::NULL);
    ops.push(op);

    graph.write_block(last, ops);

    return Ok((graph, entry));
}

pub struct TypeEnv {}

struct GraphAppend {
    block_id: u32,
    ops: Pod<GraphOp>,
}

struct CheckEnv<'a> {
    types: &'a mut TypeEnv,
    graph: &'a mut Graph,
    ids: &'a mut IdTracker,
    append: &'a mut GraphAppend,
    scope: ScopeEnv<'a>,
}

impl<'a> CheckEnv<'a> {
    fn check_block(&mut self, slot: ValueSlot, block: &Block) -> Result<Value, Error> {
        use ExprKind::*;

        for expr in block.stmts {
            let p = match *expr {
                Procedure(p) => p,
                _ => continue,
            };

            unimplemented!("procedures aren't implemented yet");
        }

        for expr in block.stmts {
            self.check_expr(ValueSlot::Delete, expr)?;
        }

        return Ok(NULL);
    }

    fn check_expr(&mut self, slot: ValueSlot, id: ExprId) -> Result<Value, Error> {
        let value = self.check_expr_inner(slot, id)?;

        return Ok(value);
    }

    fn check_expr_inner(&mut self, slot: ValueSlot, id: ExprId) -> Result<Value, Error> {
        use ExprKind::*;

        let expr = &*id;

        match *expr {
            Procedure(p) => {
                let mut ids = IdTracker::new();
                let mut proc_child = self.chain_proc(&mut ids);

                let result = proc_child.check_expr(ValueSlot::Delete, p.code)?;

                return Ok(NULL);
            }

            Integer(value) => {
                let target = self.register_id();

                let kind = GraphOpKind::ConstantU64 { target, value };
                let op = GraphOp::new(kind, Type::U64, id);
                self.append.ops.push(op);

                return Ok(Value::new(target, Type::U64));
            }

            Let { symbol, value } => {
                // TODO fix in a sec
                let var_id = self.reserve_var_id();
                let slot = ValueSlot::StackLocation { id: var_id };

                let result = self.check_expr(slot, value)?;
                let info = VariableInfo {
                    id: var_id,
                    ty: result.ty,
                };
                self.declare(id, symbol, info)?;

                let kind = GraphOpKind::DeclareStack { size: 8 };
                let op = GraphOp::new(kind, Type::U64, value);
                self.append.ops.push(op);

                let kind = GraphOpKind::Mov {
                    target: Operand::Null,
                    source: result.op,
                };
                let op = GraphOp::new(kind, Type::U64, id);
                self.append.ops.push(op);

                return Ok(NULL);
            }

            Ident { symbol } => {
                let var_info = match self.search(symbol) {
                    Some(e) => e,
                    None => {
                        return Err(Error::new("couldn't find variable", id.loc()));
                    }
                };

                let target = self.register_id();

                let kind = GraphOpKind::Mov {
                    target,
                    source: Operand::StackLocal { id: var_info.id },
                };
                let op = GraphOp::new(kind, var_info.ty, id);
                self.append.ops.push(op);

                return Ok(Value::new(target, var_info.ty));
            }

            If { cond, if_true } => {
                let end_block = self.graph.get_block_id();

                // let var_id = self.reserve_var_id();

                // let if_true_block_id = self.graph.get_block_id();
                // let if_true_arm = Arm {
                //     block_id: if_true_block_id,
                //     expr: if_true,
                // };

                // let value = self.check_arms(var_id, end_block, &[if_true_arm])?;

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
                let left_value = self.check_expr(ValueSlot::SaveSomewhere, left)?;
                let right_value = self.check_expr(ValueSlot::SaveSomewhere, right)?;

                if left_value.ty != right_value.ty {
                    return Err(Error::new(
                        "binary operation should be on values of similar type",
                        id.loc(),
                    ));
                }

                let target = self.register_id();

                let kind = GraphOpKind::Add {
                    target,
                    left: left_value.op,
                    right: right_value.op,
                };
                let op = GraphOp::new(kind, left_value.ty, id);
                self.append.ops.push(op);

                return Ok(Value::new(target, left_value.ty));
            }

            Block(block) => {
                let mut child = self.chain_local();

                for expr in block.stmts {
                    child.check_expr(ValueSlot::Delete, expr)?;
                }

                let count = child.scope.vars.len() as u16;
                let kind = GraphOpKind::StackDealloc { count };
                let op = GraphOp::new(kind, Type::Null, id);
                self.append.ops.push(op);

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
                    let value = self.check_expr(ValueSlot::SaveSomewhere, arg)?;

                    let kind = GraphOpKind::Print { value: value.op };
                    let op = GraphOp::new(kind, value.ty, arg);
                    self.append.ops.push(op);
                }

                let op = GraphOp::new(GraphOpKind::PrintNewline, Type::Null, id);
                self.append.ops.push(op);

                return Ok(NULL);
            }

            k => unimplemented!("{}", k.name()),
        }
    }

    // Completes the current block properly, and also completes all the blocks
    // it produces by having them jump to the exit block
    fn check_arms(
        &mut self,
        var_target: u16,
        exit_block: u32,
        arms: &[Arm],
    ) -> Result<Value, Error> {
        for &arm in arms {
            let mut append = GraphAppend {
                block_id: arm.block_id,
                ops: Pod::new(),
            };

            let mut branch = self.chain_branch(&mut append);
            branch.check_expr(ValueSlot::SaveSomewhere, arm.expr)?;
        }

        return Ok(NULL);
    }

    fn chain_local<'b>(&'b mut self) -> CheckEnv<'b> {
        return CheckEnv {
            types: self.types,
            graph: self.graph,
            ids: self.ids,
            append: self.append,
            scope: ScopeEnv {
                kind: ScopeKind::Local {
                    parent: &mut self.scope,
                },
                vars: HashMap::new(),
            },
        };
    }

    fn chain_proc<'b>(&'b mut self, ids: &'b mut IdTracker) -> CheckEnv<'b> {
        return CheckEnv {
            types: self.types,
            graph: self.graph,
            ids,
            append: self.append,
            scope: ScopeEnv {
                kind: ScopeKind::Procedure {
                    parent: &mut self.scope,
                },
                vars: HashMap::new(),
            },
        };
    }

    fn chain_branch<'b>(&'b mut self, append: &'b mut GraphAppend) -> CheckEnv<'b> {
        return CheckEnv {
            types: self.types,
            graph: self.graph,
            ids: self.ids,
            append,
            scope: ScopeEnv {
                kind: ScopeKind::Local {
                    parent: &mut self.scope,
                },
                vars: HashMap::new(),
            },
        };
    }

    fn complete_block(&mut self) {
        let block_id = self.graph.get_block_id();

        self.replace_block(GraphAppend {
            block_id,
            ops: Pod::new(),
        });
    }

    fn replace_block(&mut self, append: GraphAppend) {
        let append = core::mem::replace(self.append, append);
        self.graph.write_block(append.block_id, append.ops);
    }

    fn search(&self, symbol: u32) -> Option<VariableInfo> {
        let mut current = &self.scope;

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

    fn declare(&mut self, id: ExprId, symbol: u32, info: VariableInfo) -> Result<(), Error> {
        use std::collections::hash_map::Entry;

        let e = match self.scope.vars.entry(symbol) {
            Entry::Vacant(v) => v,
            Entry::Occupied(o) => {
                return Err(Error::new("redeclared variable", id.loc()));
            }
        };

        e.insert(info);

        return Ok(());
    }

    fn reserve_var_id(&mut self) -> u16 {
        let id = self.ids.next_variable_id;
        self.ids.next_variable_id += 1;

        return id;
    }

    fn register_id(&mut self) -> Operand {
        let id = self.ids.next_op_id;
        self.ids.next_op_id += 1;

        return Operand::RegisterValue { id };
    }
}

#[derive(Clone, Copy)]
struct Arm {
    block_id: u32,
    expr: ExprId,
}

enum ScopeKind<'a> {
    Global {},
    Procedure { parent: &'a ScopeEnv<'a> },
    Local { parent: &'a ScopeEnv<'a> },
}

#[derive(Clone, Copy)]
struct VariableInfo {
    id: u16,
    ty: Type,
}

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
}

struct IdTracker {
    next_variable_id: u16,
    next_op_id: u16,
}

impl IdTracker {
    fn new() -> Self {
        return Self {
            next_variable_id: 0,
            next_op_id: 1,
        };
    }
}
