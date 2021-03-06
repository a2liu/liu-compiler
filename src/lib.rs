// Long-term
#![allow(dead_code)]
#![allow(unused_variables)]
#![allow(unused_macros)]
#![allow(unused_braces)]
#![allow(non_upper_case_globals)]
// Short-term allows
/* */
#![allow(unused_imports)]
#![allow(unused_mut)]
/* */

#[macro_use]
extern crate lazy_static;

#[macro_use]
extern crate aliu;

extern crate alloc;

mod ast;
mod checker;
mod errors;
mod graph;
mod interp;
mod parser;
mod types;
mod util;

pub use ast::*;
pub use checker::*;
pub use errors::*;
pub use graph::*;
pub use interp::*;
pub use parser::*;
pub use types::*;
pub use util::*;

#[cfg(test)]
mod tests {
    use super::*;
    use crate::util::*;
    use codespan_reporting::term::termcolor;
    use std::io::Write;

    // #[test]
    // fn procedures() {
    //     run_on_file("procedures.liu", "");
    // }

    #[test]
    fn simple() {
        run_on_file("simple.liu", "69 73 \n69 8491 \n");
    }

    fn run_on_file(name: &str, expected: &str) {
        let mut path = "tests/".to_string();
        path.push_str(name);

        let buf = expect(std::fs::read_to_string(&path));
        let text = &buf;

        let mut files = FileDb::new();

        files.add(name, text);

        let out = match run_on_file_err(text) {
            Ok(out) => out,
            Err(e) => {
                let mut out = termcolor::Buffer::no_color();

                expect(e.render(&files, &mut out));

                let out = unsafe { core::str::from_utf8_unchecked(out.as_slice()) };

                println!("{}", out);

                panic!("{:?}", e);
            }
        };

        println!("{}", out);

        assert_eq!(&*out, expected);

        // panic!("viewing");
    }

    fn run_on_file_err(text: &str) -> Result<String, Error> {
        let mut table = StringTable::new();

        let data = lex(&mut table, 0, text)?;

        let ast = parse(&table, 0, data)?;

        let (graph, entry) = check_ast(&ast)?;

        let mut assembler = Assembler::new();

        let data = assembler.assemble(&graph, entry);

        let mut out = String::new();
        let mut interp = Interpreter::new(data, &mut out);
        interp.run().unwrap();

        return Ok(out);
    }
}
