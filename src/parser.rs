use crate::*;
use std::collections::hash_map::HashMap;

#[repr(u32)]
#[derive(Clone, Copy, PartialEq)]
pub enum Key {
    Let = 0,
    Proc,
    Type,
    Defer,
    Context,

    If,
    Else,
    Match,

    Continue,
    Break,
    For,

    Spawn,
    Wait,

    Underscore,
    Print,
}

impl Key {
    const COUNT: Self = Self::Underscore;
}

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum TokenKind {
    LParen = b'(',
    RParen = b')',
    LBracket = b'[',
    RBracket = b']',
    LBrace = b'{',
    RBrace = b'}',

    Dot = b'.',
    Comma = b',',
    Colon = b':',
    Semicolon = b';',

    Bang = b'!',
    Tilde = b'~',
    Amp = b'&',
    Caret = b'^',
    Mod = b'%',
    Star = b'*',
    Div = b'/',
    Plus = b'+',
    Dash = b'-',
    Equal = b'=',
    Lt = b'<',
    Gt = b'>',

    Equal2 = 129, // ==
    NotEqual,     // !=
    LtEq,         // <=
    GtEq,         // >=

    And, // &&
    Or,  // ||

    Directive,
    Word,
    String,
    Char,
    Number,

    Skip,
    NewlineSkip,
}

#[derive(Debug, Clone, Copy)]
pub struct Token {
    pub kind: TokenKind,
    pub data: u32,
}

impl Token {
    pub fn len(&self, table: &StringTable) -> u32 {
        match self.kind {
            TokenKind::Skip => return self.data,
            TokenKind::NewlineSkip => return self.data,

            TokenKind::Word => return table.names[self.data].len() as u32,
            TokenKind::Directive => return table.names[self.data].len() as u32 + 1,
            TokenKind::String => return table.names[self.data].len() as u32 + 2,
            TokenKind::Char => return table.names[self.data].len() as u32 + 2,
            TokenKind::Number => return table.names[self.data].len() as u32,

            TokenKind::Equal2 => return 2,
            TokenKind::LtEq => return 2,
            TokenKind::GtEq => return 2,
            TokenKind::And => return 2,
            TokenKind::Or => return 2,

            _ => return 1,
        }
    }
}

pub fn parse(table: &StringTable, file: u32, data: Pod<Token>) -> Result<Ast, Error> {
    use TokenKind::*;

    let allocator = AstAlloc::new(file);

    let mut parser = Parser {
        allocator,
        table,
        file,
        data,
        index: 0,
        text_cursor: 0,
    };

    let mut loc = CodeLoc {
        start: parser.text_cursor,
        end: parser.text_cursor,
        file,
    };

    let mut stmts = Pod::new();

    parser.pop_kinds_loop(&[Skip, NewlineSkip, Semicolon]);

    while (parser.index as usize) < parser.data.len() {
        let stmt = parser.parse_expr()?;
        stmts.push(stmt);

        parser.pop_kind(Skip);

        let before_eat = parser.index;

        parser.pop_kinds_loop(&[NewlineSkip, Semicolon]);

        if parser.index == before_eat {
            loc.end = parser.text_cursor;

            return Err(Error::expected("a newline or semicolon", loc));
        }

        parser.pop_kinds_loop(&[Skip, NewlineSkip, Semicolon]);
    }

    let stmts = parser.allocator.add_slice(&stmts);

    let block = Block { stmts };

    return Ok(Ast { block });
}

struct Parser<'a> {
    allocator: AstAlloc,
    table: &'a StringTable,
    data: Pod<Token>,
    file: u32,
    index: u32,
    text_cursor: u32,
}

impl<'a> Parser<'a> {
    fn peek(&self) -> Option<Token> {
        let tok = self.data.get(self.index as usize)?;

        return Some(*tok);
    }

    #[inline]
    fn adv(&mut self) {
        if let Some(tok) = self.peek() {
            self.text_cursor += tok.len(self.table);
            self.index += 1;
        }
    }

    fn pop(&mut self) -> Option<Token> {
        let tok = self.peek()?;

        self.text_cursor += tok.len(self.table);
        self.index += 1;

        return Some(tok);
    }

    fn pop_kind(&mut self, kind: TokenKind) -> Option<Token> {
        let tok = self.peek()?;

        if tok.kind != kind {
            return None;
        }

        self.text_cursor += tok.len(self.table);
        self.index += 1;

        return Some(tok);
    }

    fn pop_tok(&mut self, kind: TokenKind, data: u32) -> bool {
        let tok = match self.peek() {
            None => return false,
            Some(tok) => tok,
        };

        if tok.kind != kind || tok.data != data {
            return false;
        }

        self.text_cursor += tok.len(self.table);
        self.index += 1;

        return true;
    }

    fn pop_kinds_loop(&mut self, kinds: &[TokenKind]) -> CopyRange<u32> {
        let start = self.text_cursor;

        'outer: while let Some(tok) = self.peek() {
            for &kind in kinds {
                if tok.kind == kind {
                    self.text_cursor += tok.len(self.table);
                    self.index += 1;
                    continue 'outer;
                }
            }

            break;
        }

        return r(start, self.text_cursor);
    }

    pub fn parse_expr(&mut self) -> Result<Expr, Error> {
        return self.parse_decl();
    }

    pub fn parse_decl(&mut self) -> Result<Expr, Error> {
        if let Some(expr) = self.parse_proc()? {
            return Ok(expr);
        }

        if let Some(expr) = self.parse_let()? {
            return Ok(expr);
        }

        if let Some(expr) = self.parse_assign()? {
            return Ok(expr);
        }

        if let Some(expr) = self.parse_control()? {
            return Ok(expr);
        }

        return self.parse_binary_op();
    }

    pub fn parse_proc(&mut self) -> Result<Option<Expr>, Error> {
        use TokenKind::*;

        let mut loc = CodeLoc {
            start: self.text_cursor,
            end: self.text_cursor,
            file: self.file,
        };

        if !self.pop_tok(Word, Key::Proc as u32) {
            return Ok(None);
        };

        self.pop_kinds_loop(&[Skip]);

        let symbol = match self.pop_kind(Word) {
            Some(tok) => {
                if tok.data < Key::COUNT as u32 {
                    loc.end = self.text_cursor;

                    return Err(Error::expected("a procedure name", loc));
                }

                tok.data
            }
            None => {
                loc.end = self.text_cursor;

                return Err(Error::expected("a procedure name", loc));
            }
        };

        if self.pop_kind(LParen).is_none() {
            loc.end = self.text_cursor;

            return Err(Error::expected("opening parenthesis", loc));
        }

        self.pop_kinds_loop(&[Skip, NewlineSkip]);

        if self.pop_kind(RParen).is_none() {
            loc.end = self.text_cursor;

            return Err(Error::expected("opening closing parenthesis", loc));
        }

        self.pop_kinds_loop(&[Skip, NewlineSkip]);

        let code = match self.parse_control()? {
            Some(e) => e,
            None => {
                loc.end = self.text_cursor;

                return Err(Error::expected("a block", loc));
            }
        };

        let code = self.allocator.make(code);

        let kind = ExprKind::Procedure(Proc { symbol, code });

        return Ok(Some(Expr { kind, loc }));
    }

    pub fn parse_let(&mut self) -> Result<Option<Expr>, Error> {
        use TokenKind::*;

        let mut loc = CodeLoc {
            start: self.text_cursor,
            end: self.text_cursor,
            file: self.file,
        };

        if !self.pop_tok(Word, Key::Let as u32) {
            return Ok(None);
        };

        self.pop_kinds_loop(&[Skip, NewlineSkip]);

        let ident = match self.pop_kind(Word) {
            Some(tok) => tok,
            None => {
                loc.end = self.text_cursor;

                return Err(Error::expected("an identifer", loc));
            }
        };

        if ident.data < Key::COUNT as u32 {
            loc.end = self.text_cursor;

            return Err(Error::expected("an identifer", loc));
        }

        self.pop_kinds_loop(&[Skip, NewlineSkip]);

        let equal_start = self.text_cursor;
        match self.pop() {
            Some(Token { kind: Equal, .. }) => {}

            Some(_) | None => {
                loc.start = equal_start;
                loc.end = self.text_cursor;

                return Err(Error::expected("an equal sign", loc));
            }
        }

        self.pop_kinds_loop(&[Skip, NewlineSkip]);

        let value = match self.parse_control()? {
            Some(e) => e,
            None => self.parse_binary_op()?,
        };

        let value = self.allocator.make(value);

        loc.end = self.text_cursor;
        let kind = ExprKind::Let {
            symbol: ident.data,
            value,
        };

        return Ok(Some(Expr { kind, loc }));
    }

    pub fn parse_assign(&mut self) -> Result<Option<Expr>, Error> {
        return Ok(None);
    }

    pub fn parse_control(&mut self) -> Result<Option<Expr>, Error> {
        use TokenKind::*;

        let mut loc = CodeLoc {
            start: self.text_cursor,
            end: self.text_cursor,
            file: self.file,
        };

        // if, else
        if self.pop_tok(Word, Key::If as u32) {
            self.pop_kinds_loop(&[Skip, NewlineSkip]);

            let cond = self.parse_binary_op()?;
            let cond = self.allocator.make(cond);

            let control_start = self.text_cursor;
            let if_true = match self.parse_control()? {
                Some(e) => self.allocator.make(e),
                None => {
                    loc.start = control_start;
                    loc.end = self.text_cursor;

                    return Err(Error::expected("control flow or block", loc));
                }
            };

            if !self.pop_tok(Word, Key::Else as u32) {
                loc.end = self.text_cursor;
                let kind = ExprKind::If { cond, if_true };

                return Ok(Some(Expr { kind, loc }));
            }

            let control_start = self.text_cursor;
            let if_false = match self.parse_control()? {
                Some(e) => self.allocator.make(e),
                None => {
                    loc.start = control_start;
                    loc.end = self.text_cursor;

                    return Err(Error::expected("control flow or block", loc));
                }
            };

            loc.end = self.text_cursor;
            let kind = ExprKind::IfElse {
                cond,
                if_true,
                if_false,
            };

            return Ok(Some(Expr { kind, loc }));
        }

        // case

        // for

        // block
        if let Some(_) = self.pop_kind(LBrace) {
            use TokenKind::*;

            let mut stmts = Pod::new();

            self.pop_kinds_loop(&[Skip, NewlineSkip, Semicolon]);

            if self.pop_kind(RBrace).is_some() {
                loc.end = self.text_cursor;

                let block = Block {
                    stmts: ExprRange::EMPTY,
                };

                let kind = ExprKind::Block(block);

                return Ok(Some(Expr { kind, loc }));
            }

            // TODO track indentation of braces, for nice reporting
            // of matching closing braces.
            //                         - Albert Liu, Mar 04, 2022 Fri 01:14 EST
            loop {
                let stmt = self.parse_expr()?;
                stmts.push(stmt);

                self.pop_kind(Skip);

                let before_eat = self.index;

                self.pop_kinds_loop(&[NewlineSkip, Semicolon]);

                if self.pop_kind(RBrace).is_some() {
                    loc.end = self.text_cursor;

                    break;
                }

                if self.index == before_eat {
                    loc.end = self.text_cursor;

                    return Err(Error::expected("a newline or semicolon", loc));
                }

                self.pop_kinds_loop(&[Skip, NewlineSkip, Semicolon]);
            }

            let stmts = self.allocator.add_slice(&stmts);

            let block = Block { stmts };

            let kind = ExprKind::Block(block);

            return Ok(Some(Expr { kind, loc }));
        }

        return Ok(None);
    }

    pub fn parse_binary_op(&mut self) -> Result<Expr, Error> {
        return self.parse_binary_precedence_op(0);
    }

    pub fn parse_binary_precedence_op(&mut self, min_level: u8) -> Result<Expr, Error> {
        use TokenKind::*;

        let mut loc = CodeLoc {
            start: self.text_cursor,
            end: self.text_cursor,
            file: self.file,
        };

        let mut expr = self.parse_prefix()?;

        self.pop_kinds_loop(&[Skip]);

        // https://eli.thegreenplace.net/2012/08/02/parsing-expressions-by-precedence-climbing
        // This algorithm is supposed to be efficient. No idea if that's actually true,
        // but it is incredibly concise.
        while let Some(tok) = self.peek() {
            let info = OPERATORS[tok.kind as usize];
            if info.precedence < min_level {
                break;
            }

            let kind = match info.op_kind {
                Some(kind) => kind,
                None => break,
            };

            self.adv();

            let mut next_min_level = info.precedence;
            if info.is_left_to_right {
                next_min_level += 1;
            }

            self.pop_kinds_loop(&[Skip, NewlineSkip]);

            let right = self.parse_binary_precedence_op(next_min_level)?;

            if let Some(check) = info.check_operands {
                check(&expr, &right)?;
            }

            loc.end = right.loc.end;

            let left = self.allocator.make(expr);
            let right = self.allocator.make(right);

            let kind = ExprKind::BinaryOp { kind, left, right };

            expr = Expr { kind, loc };

            self.pop_kinds_loop(&[Skip]);
        }

        return Ok(expr);
    }

    pub fn parse_prefix(&mut self) -> Result<Expr, Error> {
        use TokenKind::*;

        let mut loc = CodeLoc {
            start: self.text_cursor,
            end: self.text_cursor,
            file: self.file,
        };

        return self.parse_postfix();
    }

    pub fn parse_postfix(&mut self) -> Result<Expr, Error> {
        use TokenKind::*;

        let mut loc = CodeLoc {
            start: self.text_cursor,
            end: self.text_cursor,
            file: self.file,
        };

        let mut expr = self.parse_atom()?;

        self.pop_kinds_loop(&[Skip]);

        while let Some(tok) = self.peek() {
            match tok.kind {
                LParen => {
                    self.adv();

                    self.pop_kinds_loop(&[Skip, NewlineSkip]);

                    if self.pop_kind(RParen).is_some() {
                        loc.end = self.text_cursor;

                        let callee = self.allocator.make(expr);
                        let kind = ExprKind::Call {
                            callee,
                            args: ExprRange::EMPTY,
                        };

                        expr = Expr { kind, loc };
                        continue;
                    }

                    let mut args = Pod::new();
                    loop {
                        let expr = self.parse_binary_op()?;
                        args.push(expr);

                        let before_comma = self.text_cursor;

                        self.pop_kinds_loop(&[Skip, NewlineSkip]);

                        let found_comma = self.pop_kind(Comma).is_some();

                        self.pop_kinds_loop(&[Skip, NewlineSkip]);

                        if self.pop_kind(RParen).is_some() {
                            loc.end = self.text_cursor;

                            break;
                        }

                        if !found_comma {
                            loc.start = before_comma;
                            loc.end = before_comma;

                            return Err(Error::expected("a comma or closing paren", loc));
                        }
                    }

                    let callee = self.allocator.make(expr);
                    let args = self.allocator.add_slice(&args);

                    loc.end = self.text_cursor;
                    let kind = ExprKind::Call { callee, args };

                    expr = Expr { kind, loc };
                }

                _ => break,
            }
        }

        return Ok(expr);
    }

    pub fn parse_atom(&mut self) -> Result<Expr, Error> {
        use TokenKind::*;

        let mut loc = CodeLoc {
            start: self.text_cursor,
            end: self.text_cursor,
            file: self.file,
        };

        let result = self.pop();
        let tok = result.ok_or_else(|| {
            return Error::expected("an expression", loc);
        })?;

        match tok.kind {
            Word => {
                if tok.data < Key::COUNT as u32 && tok.data != Key::Type as u32 {
                    loc.end = self.text_cursor;

                    return Err(Error::expected("an identifer", loc));
                }

                loc.end = self.text_cursor;
                let kind = ExprKind::Ident { symbol: tok.data };

                return Ok(Expr { kind, loc });
            }

            Number => {
                let data = self.table.names[tok.data];

                let mut index = 0;
                let mut total: u64 = 0;

                // NOTE: just assume its an integer for now
                for &b in data.as_bytes() {
                    if b < b'0' || b'9' < b {
                        loc.start = loc.start + index;
                        loc.end = loc.start + 1;

                        return Err(Error::expected("a digit in a number", loc));
                    }

                    total *= 10;
                    total += (b - b'0') as u64;

                    index += 1;
                }

                loc.end = self.text_cursor;
                let kind = ExprKind::Integer(total);

                return Ok(Expr { kind, loc });
            }

            LParen => {
                self.pop_kinds_loop(&[Skip, NewlineSkip]);

                let expr = self.parse_expr()?;

                self.pop_kinds_loop(&[Skip, NewlineSkip]);

                match self.pop_kind(RParen) {
                    Some(tok) => return Ok(expr),
                    None => {
                        loc.end = self.text_cursor;

                        return Err(Error::expected("a closing parenthesis", loc));
                    }
                }
            }

            _ => {
                loc.end = self.text_cursor;

                return Err(Error::expected("an expression", loc));
            }
        }
    }
}

#[derive(Clone, Copy)]
struct OperatorInfo {
    op_kind: Option<BinaryExprKind>,
    precedence: u8,
    is_left_to_right: bool,

    // @TODO this should be something like make_expr : (left, right) -> Result(*Expr)
    // So that we can make assignment expressions a lil nicer right off the bat
    check_operands: Option<fn(left: &Expr, right: &Expr) -> Result<(), Error>>,
}

const OPERATORS: [OperatorInfo; 256] = {
    let default_info = OperatorInfo {
        op_kind: None,
        precedence: 0,
        is_left_to_right: true,
        check_operands: None,
    };

    let mut info = [default_info; 256];
    let mut idx;

    idx = TokenKind::Equal2 as usize;
    info[idx].op_kind = Some(BinaryExprKind::Equal);
    info[idx].precedence = 10;

    idx = TokenKind::Plus as usize;
    info[idx].op_kind = Some(BinaryExprKind::Add);
    info[idx].precedence = 50;

    idx = TokenKind::Star as usize;
    info[idx].op_kind = Some(BinaryExprKind::Multiply);
    info[idx].precedence = 60;

    info
};

pub fn lex(table: &mut StringTable, file: u32, s: &str) -> Result<Pod<Token>, Error> {
    let mut tokens = Pod::new();
    let bytes = s.as_bytes();

    let mut index = 0;
    'outer: while let Some(&b) = bytes.get(index) {
        let start = index;
        index += 1;

        'simple: loop {
            macro_rules! trailing_eq {
                ($e1:expr, $e2:expr) => {{
                    if let Some(b'=') = bytes.get(index) {
                        index += 1;

                        $e2
                    } else {
                        $e1
                    }
                }};
            }

            let kind = match b {
                b'(' => TokenKind::LParen,
                b')' => TokenKind::RParen,
                b'[' => TokenKind::LBracket,
                b']' => TokenKind::RBracket,
                b'{' => TokenKind::LBrace,
                b'}' => TokenKind::RBrace,
                b'.' => TokenKind::Dot,
                b',' => TokenKind::Comma,
                b':' => TokenKind::Colon,
                b';' => TokenKind::Semicolon,
                b'~' => TokenKind::Tilde,
                b'&' => TokenKind::Amp,
                b'^' => TokenKind::Caret,

                b'!' => trailing_eq!(TokenKind::Bang, TokenKind::NotEqual),
                b'=' => trailing_eq!(TokenKind::Equal, TokenKind::Equal2),
                b'<' => trailing_eq!(TokenKind::Lt, TokenKind::LtEq),
                b'>' => trailing_eq!(TokenKind::Gt, TokenKind::GtEq),

                // b'/' is handled separately because comments have more complex
                // syntax checking
                b'%' => TokenKind::Mod,
                b'*' => TokenKind::Star,
                b'+' => TokenKind::Plus,
                b'-' => TokenKind::Dash,

                _ => break 'simple,
            };

            tokens.push(Token { kind, data: 0 });
            continue 'outer;
        }

        if b == b'"' {
            let end = parse_string(file, bytes, index, b'"')?;
            let s = unsafe { core::str::from_utf8_unchecked(&bytes[index..(end - 1)]) };
            let data = table.add(s);

            index = end;

            let kind = TokenKind::String;
            tokens.push(Token { kind, data });
            continue 'outer;
        }

        if b == b'\'' {
            let end = parse_string(file, bytes, index, b'\'')?;
            let s = unsafe { core::str::from_utf8_unchecked(&bytes[index..(end - 1)]) };
            let data = table.add(s);

            index = end;

            let kind = TokenKind::Char;
            tokens.push(Token { kind, data });
            continue 'outer;
        }

        if b == b'/' {
            if let Some(b'/') = bytes.get(index) {
                index += 1;

                while let Some(&b) = bytes.get(index) {
                    index += 1;

                    if b == b'\n' {
                        break;
                    }
                }

                let kind = TokenKind::Skip;
                let data: u32 = expect((index - start).try_into());
                tokens.push(Token { kind, data });
                continue 'outer;
            }

            let kind = TokenKind::Div;
            tokens.push(Token { kind, data: 0 });
            continue 'outer;
        }

        let is_alpha = (b >= b'a' && b <= b'z') || (b >= b'A' && b <= b'Z');
        let is_num = b >= b'0' && b <= b'9';
        if is_alpha || is_num || b == b'_' {
            while let Some(&b) = bytes.get(index) {
                let is_alpha = (b >= b'a' && b <= b'z') || (b >= b'A' && b <= b'Z');
                let is_num = b >= b'0' && b <= b'9';

                if is_alpha || is_num || b == b'_' {
                    index += 1;
                    continue;
                }

                break;
            }

            let kind = match is_num {
                false => TokenKind::Word,

                true => {
                    if let Some(b'.') = bytes.get(index).map(|b| *b) {
                        index += 1;

                        while let Some(&b) = bytes.get(index) {
                            let is_alpha = (b >= b'a' && b <= b'z') || (b >= b'A' && b <= b'Z');
                            let is_num = b >= b'0' && b <= b'9';

                            if is_alpha || is_num || b == b'_' {
                                index += 1;
                                continue;
                            }

                            break;
                        }
                    }

                    TokenKind::Number
                }
            };

            let s = unsafe { core::str::from_utf8_unchecked(&bytes[start..index]) };
            let data = table.add(s);

            tokens.push(Token { kind, data });
            continue 'outer;
        }

        let is_newline = b == b'\n';
        if b == b' ' || b == b'\t' || b == b'\r' || is_newline {
            let mut has_newline = is_newline;

            while let Some(&b) = bytes.get(index) {
                let is_newline = b == b'\n';
                if is_newline {
                    has_newline = true;
                    index += 1;

                    continue;
                }

                if b == b' ' || b == b'\t' || b == b'\r' {
                    index += 1;

                    continue;
                }

                break;
            }

            let kind = match has_newline {
                true => TokenKind::NewlineSkip,
                false => TokenKind::Skip,
            };

            let data: u32 = expect((index - start).try_into());
            tokens.push(Token { kind, data });
            continue 'outer;
        }

        let loc = CodeLoc {
            file,
            start: start as u32,
            end: index as u32,
        };

        let error = Error::new("unrecognized token", loc);
        return Err(error);
    }

    return Ok(tokens);
}

fn parse_string(file: u32, bytes: &[u8], mut index: usize, terminator: u8) -> Result<usize, Error> {
    let start = index;

    let mut escaped = false;
    while let Some(&b) = bytes.get(index) {
        index += 1;

        if b == b'\\' {
            escaped = true;
            continue;
        }

        if b == b'"' && !escaped {
            return Ok(index);
        }

        escaped = false;
    }

    let loc = CodeLoc {
        file,
        start: start as u32,
        end: index as u32,
    };

    return Err(Error::new("failed to parse char or string", loc));
}

pub struct StringTable {
    allocator: BucketList,
    pub names: Pod<&'static str>,
    pub translate: HashMap<&'static str, u32>,
}

impl StringTable {
    pub fn new() -> Self {
        let mut table = Self {
            allocator: BucketList::new(),
            names: Pod::new(),
            translate: HashMap::new(),
        };

        let mut success = true;

        success = success && table.add("let") == Key::Let as u32;
        success = success && table.add("proc") == Key::Proc as u32;
        success = success && table.add("type") == Key::Type as u32;
        success = success && table.add("defer") == Key::Defer as u32;
        success = success && table.add("context") == Key::Context as u32;

        success = success && table.add("if") == Key::If as u32;
        success = success && table.add("else") == Key::Else as u32;
        success = success && table.add("match") == Key::Match as u32;

        success = success && table.add("continue") == Key::Continue as u32;
        success = success && table.add("break") == Key::Break as u32;
        success = success && table.add("for") == Key::For as u32;

        success = success && table.add("spawn") == Key::Spawn as u32;
        success = success && table.add("wait") == Key::Wait as u32;

        success = success && table.add("_") == Key::Underscore as u32;
        success = success && table.add("print") == Key::Print as u32;

        if !success {
            panic!("Rippo");
        }

        table
    }

    pub fn add(&mut self, s: &str) -> u32 {
        if let Some(id) = self.translate.get(s) {
            return *id;
        }

        let s = self.allocator.add_str(s);
        let id = self.names.len() as u32;

        self.translate.insert(s, id);
        self.names.push(s);

        return id;
    }
}
