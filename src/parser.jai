#import "Basic";
#import "hashmap";
#import "strings";
#import "write";

AstNode :: struct {
    file: s32;
    begin: s32;
    end: s32;
}

BinaryOpKind :: enum {
}

ExprNode :: struct {
    Kind :: enum {
        BINARY_OP;
        REF;
    }

    Data :: union {
        binary_op_data: struct {
            op: BinaryOpKind;
            left: *ExprNode;
            right: *ExprNode;
        };
    }

    using base: AstNode;
    kind: Kind;
    using data: Data;
}
