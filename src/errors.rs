use crate::*;
use codespan_reporting::diagnostic::{Diagnostic, Label};
use codespan_reporting::term;
use core::fmt::{self, Error as FmtError, Result as FmtResult, Write};

// TODO Placeholder system. Eventually we'll flesh this out maybe. For now, 'tis
// a simple thing with a bit of needless complexity
//                              - Albert Liu, Jan 23, 2022 Sun 22:21 EST
#[derive(Debug, PartialEq, Hash)]
pub enum Error {
    Simple { message: String, loc: CodeLoc },
    StaticSimple { message: &'static str, loc: CodeLoc },
}

#[derive(Debug)]
pub struct ErrorMessage {
    message: String,
    loc: CodeLoc,
}

impl Error {
    pub fn render(
        &self,
        files: &FileDb,
        out: &mut impl term::termcolor::WriteColor,
    ) -> fmt::Result {
        let mut out_labels = Vec::new();
        let mut out_message: String;

        match self {
            Error::Simple { message, loc } => {
                out_labels.push(loc.primary().with_message(""));

                out_message = message.to_string();
            }

            Error::StaticSimple { message, loc } => {
                out_labels.push(loc.primary().with_message(""));

                out_message = message.to_string();
            }
        };

        let diagnostic = Diagnostic::error()
            .with_message(&out_message)
            .with_labels(out_labels);

        let config = codespan_reporting::term::Config::default();
        return term::emit(out, &config, &files, &diagnostic).map_err(|_| core::fmt::Error);
    }
}

impl Error {
    pub fn new(s: impl Into<String>, loc: CodeLoc) -> Self {
        return Self::Simple {
            message: s.into(),
            loc,
        };
    }

    pub fn expected(s: &'static str, loc: CodeLoc) -> Self {
        let mut message = String::new();
        message += "expected ";
        message += s;
        message += " here";

        return Self::Simple { message, loc };
    }
}
