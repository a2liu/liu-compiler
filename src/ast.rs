use crate::util::*;
use crate::*;

pub struct Ast {
    pub allocator: BucketList,
    pub block: Block,
}

#[derive(Debug, Clone, Copy)]
pub struct Block {
    // translation from identifier to global memory numbering
    // pub scope: HashRef<'static, u32, u32>,
    pub stmts: &'static [Expr],
}

#[derive(Debug, Clone, Copy)]
pub struct Proc {
    pub symbol: u32,
    pub code: &'static Expr,
}

#[derive(Debug, Clone, Copy)]
pub struct Expr {
    pub kind: ExprKind,
    pub loc: CodeLoc,
}

#[derive(Debug, PartialEq, Clone, Copy)]
pub enum BinaryExprKind {
    Add,
    Multiply,
    Equal,
}

#[derive(Debug, Clone, Copy)]
pub enum ExprKind {
    Integer(u64),
    Ident {
        symbol: u32,
    },

    Procedure(Proc),

    Call {
        callee: &'static Expr,
        args: &'static [Expr],
    },

    BinaryOp {
        kind: BinaryExprKind,
        left: &'static Expr,
        right: &'static Expr,
    },

    // TODO Eventually support:
    //
    // let a : int = 1
    // let a = 1
    // let a : int
    // let a
    Let {
        symbol: u32,
        value: &'static Expr,
    },

    Assign {
        symbol: u32,
        value: &'static Expr,
    },

    Block(Block),

    If {
        cond: &'static Expr,
        if_true: &'static Expr,
    },
    IfElse {
        cond: &'static Expr,
        if_true: &'static Expr,
        if_false: &'static Expr,
    },

    ForInfinite {
        block: Block,
    },
}

impl ExprKind {
    pub fn name(&self) -> &'static str {
        use ExprKind::*;

        return match self {
            Integer(v) => "Integer",
            Ident { symbol } => "Ident",
            Procedure(p) => "Procedure",
            Call { callee, args } => "Call",
            BinaryOp { kind, left, right } => "BinaryOp",
            Let { symbol, value } => "Let",
            Assign { symbol, value } => "Assign",
            Block(block) => "Block",
            If { cond, if_true } => "If",
            IfElse {
                cond,
                if_true,
                if_false,
            } => "IfElse",
            ForInfinite { block } => "ForInfinite",
        };
    }
}
