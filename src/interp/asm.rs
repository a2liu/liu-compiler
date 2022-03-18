use crate::*;

pub struct Assembler {
    pub exe_bytes: Pod<u32>,
    pub loc_bytes: Pod<u32>,
    pub current_expr: ExprId,
}

impl Assembler {
    pub fn new() -> Self {
        return Self {
            exe_bytes: Pod::with_capacity(256),
            loc_bytes: Pod::with_capacity(256),
            current_expr: ExprId::NULL,
        };
    }

    pub fn assemble(&mut self, graph: &Graph, entry_block: u32) {
        use OpKind::*;
        use Operand::*;

        let block = graph.blocks[entry_block];

        let ops = &graph.ops[block.ops];

        for &op in ops {
            match op {
                Loc { expr } => {
                    self.current_expr = expr;
                }

                _ => {
                    unimplemented!("{:?}", op);
                }
            }
        }
    }

    pub fn push(&mut self, val: impl Into<u32>) {
        self.exe_bytes.push(val.into());

        let bytes = unsafe { core::mem::transmute(self.current_expr) };
        self.loc_bytes.push(bytes);
    }
}
