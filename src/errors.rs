use crate::util::*;
use crate::*;
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
    pub fn render(&self, files: &FileDb, out: &mut impl Write) -> fmt::Result {
        let mut labels = Pod::new();

        let diagnostic = match self {
            Error::Simple { message, loc } => {
                labels.push(Label {
                    message: "",
                    loc: *loc,
                });

                Diagnostic {
                    message: message,
                    notes: &[],
                    labels: &*labels,
                }
            }

            Error::StaticSimple { message, loc } => {
                labels.push(Label {
                    message: "",
                    loc: *loc,
                });

                Diagnostic {
                    message: *message,
                    notes: &[],
                    labels: &*labels,
                }
            }
        };

        return render_diagnostic(&diagnostic, files, out);
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
