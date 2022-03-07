use crate::util::*;
use crate::*;
use core::cell::*;
use core::mem::*;
use core::sync::atomic::{AtomicUsize, Ordering};

pub struct Ast {
    pub block: Block,
}

#[derive(Debug, Clone, Copy)]
pub struct Block {
    // translation from identifier to global memory numbering
    // pub scope: HashRef<'static, u32, u32>,
    pub stmts: ExprRange,
}

#[derive(Debug, Clone, Copy)]
pub struct Proc {
    pub symbol: u32,
    pub code: ExprId,
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
        callee: ExprId,
        args: ExprRange,
    },

    BinaryOp {
        kind: BinaryExprKind,
        left: ExprId,
        right: ExprId,
    },

    // TODO Eventually support:
    //
    // let a : int = 1
    // let a = 1
    // let a : int
    // let a
    Let {
        symbol: u32,
        value: ExprId,
    },

    Assign {
        symbol: u32,
        value: ExprId,
    },

    Block(Block),

    If {
        cond: ExprId,
        if_true: ExprId,
    },
    IfElse {
        cond: ExprId,
        if_true: ExprId,
        if_false: ExprId,
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

struct AstGlobalAllocator {
    len: AtomicUsize,
    capacity: usize,
    tree: region::Allocation,
    locs: region::Allocation,
    files: region::Allocation,
}

// TODO actually figure out what numbers here would be good
const ALLOC_SIZE: usize = 32 * 1024 * 1024;
const RANGE_BYTES_SIZE: usize = 1024;
const RANGE_SIZE: usize = RANGE_BYTES_SIZE / core::mem::size_of::<ExprKind>();

unsafe impl Sync for AstGlobalAllocator {}

lazy_static! {
    static ref AST_ALLOC: AstGlobalAllocator = {
        let tree = expect(region::alloc(ALLOC_SIZE, region::Protection::READ_WRITE));

        let capacity = tree.len() / core::mem::size_of::<ExprKind>();
        let range_count = capacity / RANGE_SIZE;
        let capacity = range_count * RANGE_SIZE;

        let locs = expect(region::alloc(
            capacity * core::mem::size_of::<CopyRange>(),
            region::Protection::READ_WRITE,
        ));

        let files = expect(region::alloc(
            range_count * core::mem::size_of::<u32>(),
            region::Protection::READ_WRITE,
        ));

        AstGlobalAllocator {
            len: AtomicUsize::new(0),
            capacity,
            tree,
            locs,
            files,
        }
    };
}

#[derive(Hash, PartialEq, Eq, Debug, Clone, Copy)]
pub struct ExprId(u32);

#[derive(Debug, Clone, Copy)]
pub struct ExprRange(u32, u32);

impl ExprRange {
    pub const EMPTY: Self = Self(0, 0);
}

impl core::ops::Deref for ExprId {
    type Target = ExprKind;

    fn deref(&self) -> &ExprKind {
        let arena = &*AST_ALLOC;

        unsafe {
            let exprs = arena.tree.as_ptr() as *const ExprKind;
            let exprs = core::slice::from_raw_parts(exprs, arena.capacity);

            let index = self.0 as usize;

            return &exprs[index];
        }
    }
}

impl core::ops::Deref for ExprRange {
    type Target = [ExprKind];

    fn deref(&self) -> &[ExprKind] {
        let arena = &*AST_ALLOC;

        unsafe {
            let exprs = arena.tree.as_ptr() as *const ExprKind;
            let exprs = core::slice::from_raw_parts(exprs, arena.capacity);

            let start = self.0 as usize;
            let end = self.1 as usize;

            return &exprs[start..end];
        }
    }
}

impl IntoIterator for ExprRange {
    type Item = ExprId;
    type IntoIter = ExprRangeIter;

    fn into_iter(self) -> ExprRangeIter {
        return ExprRangeIter {
            start: self.0,
            end: self.1,
        };
    }
}

pub struct ExprRangeIter {
    start: u32,
    end: u32,
}

impl Iterator for ExprRangeIter {
    type Item = ExprId;

    fn next(&mut self) -> Option<ExprId> {
        if self.start >= self.end {
            return None;
        }

        let id = self.start;
        self.start += 1;

        return Some(ExprId(id));
    }
}

impl ExprId {
    pub fn loc(self) -> CodeLoc {
        let arena = &*AST_ALLOC;

        unsafe {
            let files = arena.files.as_ptr() as *const u32;
            let locs = arena.locs.as_ptr() as *const CopyRange;

            let files = core::slice::from_raw_parts(files, arena.capacity / RANGE_SIZE);
            let locs = core::slice::from_raw_parts(locs, arena.capacity);

            let index = self.0 as usize;

            let loc = locs[index];

            return CodeLoc {
                start: loc.start,
                end: loc.end,
                file: files[index / RANGE_SIZE],
            };
        }
    }
}

pub struct AstAlloc {
    file: u32,
    current: u32,
    end: u32,

    tree: *const ExprKind,
    locs: *const CopyRange,
    files: *const u32,
}

impl AstAlloc {
    pub fn new(file: u32) -> Self {
        let arena = &*AST_ALLOC;

        let tree = arena.tree.as_ptr() as *const ExprKind;
        let files = arena.files.as_ptr() as *const u32;
        let locs = arena.locs.as_ptr() as *const CopyRange;

        return Self {
            file,
            current: 0,
            end: 0,

            tree,
            locs,
            files,
        };
    }

    fn reserve(&mut self, count: usize) {
        if count <= self.end as usize - self.current as usize {
            return;
        }

        // round up count to range boundary
        let range_count = (count - 1) / RANGE_SIZE + 1;
        let count = range_count * RANGE_SIZE;

        let arena = &*AST_ALLOC;

        let current = arena.len.fetch_add(count, Ordering::SeqCst);
        let end = current + count;

        if end > arena.capacity {
            panic!("ran out of space");
        }

        self.current = current as u32;
        self.end = end as u32;

        unsafe {
            let files = self.files as *mut u32;
            let files = files.add(self.current as usize / RANGE_SIZE);
            let files = core::slice::from_raw_parts_mut(files, range_count);

            files.fill(self.file);
        }
    }

    pub fn make(&mut self, expr: Expr) -> ExprId {
        self.reserve(1);

        let index = self.current;
        self.current += 1;

        unsafe {
            let index = index as usize;

            let e = self.tree as *mut ExprKind;
            let e = e.add(index);
            *e = expr.kind;

            let loc = self.locs as *mut CopyRange;
            let loc = loc.add(index);
            let range = CopyRange {
                start: expr.loc.start,
                end: expr.loc.end,
            };
            *loc = range;
        }

        return ExprId(index);
    }

    pub fn add_slice(&mut self, spanned_exprs: &[Expr]) -> ExprRange {
        let len = spanned_exprs.len();
        self.reserve(len);

        let index = self.current;
        self.current += len as u32;

        unsafe {
            let index = index as usize;

            let exprs = self.tree as *mut ExprKind;
            let exprs = exprs.add(index);

            let locs = self.locs as *mut CopyRange;
            let locs = locs.add(index);

            let exprs = core::slice::from_raw_parts_mut(exprs, len);
            let locs = core::slice::from_raw_parts_mut(locs, len);

            for (i, expr) in spanned_exprs.into_iter().enumerate() {
                exprs[i] = expr.kind;
                locs[i].start = expr.loc.start;
                locs[i].end = expr.loc.end;
            }
        }

        return ExprRange(index, index + len as u32);
    }
}

#[test]
fn ast() {
    fn make_tree() {
        let mut ast_alloc = AstAlloc::new(0);

        for i in 0usize..64 {
            let id = ast_alloc.make(Expr {
                kind: ExprKind::Integer(i as u64),
                loc: CodeLoc {
                    start: i,
                    end: i + 1,
                    file: 0,
                },
            });

            println!("{:?} {:?} {:?}", id, *id, id.loc());
        }
    }

    let t1 = std::thread::spawn(make_tree);
    let t2 = std::thread::spawn(make_tree);
    let t3 = std::thread::spawn(make_tree);

    t1.join().expect("idk");
    t2.join().expect("idk");
    t3.join().expect("idk");
}
