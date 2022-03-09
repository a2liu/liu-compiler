use crate::util::*;
use codespan_reporting::diagnostic::Label;
use codespan_reporting::files;
use core::fmt::{self, Error as FmtError, Result as FmtResult, Write};
use core::ops::Range;
use core::str;
use core::sync::atomic::{AtomicU32, Ordering};
use std::collections::hash_map::HashMap;

#[derive(Clone, Copy, Hash, PartialEq, Eq)]
pub struct CodeLoc {
    pub start: u32,
    pub end: u32,
    pub file: u32,
}

impl CodeLoc {
    pub fn primary(&self) -> Label<u32> {
        return Label::primary(self.file, (self.start as usize)..(self.end as usize));
    }
}

impl fmt::Debug for CodeLoc {
    fn fmt(&self, fmt: &mut fmt::Formatter) -> Result<(), fmt::Error> {
        write!(fmt, "{}:({},{})", self.file, self.start, self.end)
    }
}

#[derive(Debug, Clone, Copy)]
pub struct File<'a> {
    pub name: &'a str,
    /// The source code of the file.
    pub source: &'a str,
    /// The starting byte indices in the source code.
    pub line_starts: &'a [usize],
}

impl<'a> File<'a> {
    pub fn new(buckets: impl Allocator, name: &str, source: &str) -> Self {
        let line_starts: Pod<usize> = files::line_starts(source).collect();

        return File {
            name: buckets.add_str(name),
            source: buckets.add_str(source),
            line_starts: buckets.add_slice(&line_starts),
        };
    }

    fn line_index(&self, byte_index: usize) -> Option<usize> {
        return match self.line_starts.binary_search(&byte_index) {
            Ok(line) => Some(line),
            Err(next_line) => Some(next_line - 1),
        };
    }

    fn line_start(&self, line_index: usize) -> Option<usize> {
        use core::cmp::Ordering;

        return match line_index.cmp(&self.line_starts.len()) {
            Ordering::Less => self.line_starts.get(line_index).cloned(),
            Ordering::Equal => Some(self.source.len()),
            Ordering::Greater => None,
        };
    }

    fn line_range(&self, line_index: usize) -> Option<core::ops::Range<usize>> {
        let line_start = self.line_start(line_index)?;
        let next_line_start = self.line_start(line_index + 1)?;

        return Some(line_start..next_line_start);
    }
}

pub struct FileDb {
    pub buckets: BucketList,
    pub names: HashMap<(bool, &'static str), u32>,
    pub files: Pod<File<'static>>,
}

impl FileDb {
    #[inline]
    pub fn new() -> Self {
        let mut new_self = Self {
            buckets: BucketList::new(),
            files: Pod::new(),
            names: HashMap::new(),
        };

        new_self
    }

    /// Add a file to the database, returning the handle that can be used to
    /// refer to it again. Errors if the file already exists in the database.
    pub fn add(&mut self, file_name: &str, source: &str) -> u32 {
        if let Some(id) = self.names.get(&(false, file_name)) {
            // TODO this is probably an error, idk
            return *id;
        }

        let file_id = self.files.len() as u32;
        let file = File::new(&self.buckets, file_name, &source);
        self.files.push(file);
        self.names.insert((false, file.name), file_id);

        return file_id;
    }

    pub fn display_loc(&self, out: &mut impl fmt::Write, loc: CodeLoc) -> fmt::Result {
        let file = self.files[loc.file as usize];
        let start_line = file.line_index(loc.start as usize).unwrap();
        let end_line = file.line_index(loc.end as usize).unwrap();

        let start = file.line_start(start_line).unwrap();
        let end = file.line_start(end_line + 1).unwrap();
        let bytes = &file.source.as_bytes()[start..end];

        return write!(out, "{}", unsafe { str::from_utf8_unchecked(bytes) });
    }

    pub fn write_loc(&self, out: &mut impl fmt::Write, loc: CodeLoc) -> fmt::Result {
        let file = self.files[loc.file as usize];
        let line = file.line_index(loc.start as usize).unwrap() + 1;
        return write!(out, "{}:{}", file.name, line);
    }

    pub fn loc_to_string(&self, loc: CodeLoc) -> String {
        let mut out = String::new();
        self.write_loc(&mut out, loc).unwrap();
        return out;
    }

    pub fn line_index(&self, file_id: u32, byte_index: usize) -> Option<usize> {
        let file = self.files.get(file_id as usize)?;
        return file.line_index(byte_index);
    }

    pub fn line_range(&self, file_id: u32, line_index: usize) -> Option<core::ops::Range<usize>> {
        let file = self.files.get(file_id as usize)?;
        return file.line_range(line_index);
    }
}

impl<'a> files::Files<'a> for &'a FileDb {
    type FileId = u32;
    type Name = &'static str;
    type Source = &'static str;

    fn name(&'a self, file_id: u32) -> Result<&'static str, files::Error> {
        let file = self
            .files
            .get(file_id as usize)
            .ok_or_else(|| files::Error::FileMissing)?;

        return Ok(file.name);
    }

    fn source(&'a self, file_id: u32) -> Result<&'static str, files::Error> {
        let file = self
            .files
            .get(file_id as usize)
            .ok_or_else(|| files::Error::FileMissing)?;

        return Ok(file.source);
    }

    fn line_index(&'a self, file_id: u32, byte_index: usize) -> Result<usize, files::Error> {
        let file = self
            .files
            .get(file_id as usize)
            .ok_or_else(|| files::Error::FileMissing)?;

        return match file.line_starts.binary_search(&byte_index) {
            Ok(line) => Ok(line),
            Err(next_line) => Ok(next_line - 1),
        };
    }

    fn line_range(&'a self, file_id: u32, line_index: usize) -> Result<Range<usize>, files::Error> {
        let file = self
            .files
            .get(file_id as usize)
            .ok_or_else(|| files::Error::FileMissing)?;

        let begin = file.line_starts[line_index];
        let end = file
            .line_starts
            .get(line_index + 1)
            .map(|i| *i)
            .unwrap_or(file.source.len());

        return Ok(begin..end);
    }
}

#[cfg(not(target_os = "windows"))]
const PATH_SEP: u8 = b'/';
#[cfg(target_os = "windows")]
const PATH_SEP: u8 = b'\\';

pub fn parent_if_file<'a>(path: &'a str) -> &'a str {
    let bytes = path.as_bytes();
    let mut idx = bytes.len() - 1;
    while bytes[idx] != PATH_SEP {
        if idx == 0 {
            return ""; // idk man this works
        }
        idx -= 1;
    }

    unsafe { str::from_utf8_unchecked(&bytes[..(idx + 1)]) }
}

// https://github.com/danreeves/path-clean/blob/master/src/lib.rs
pub fn path_clean(path: &str) -> String {
    let out = clean_internal(path.as_bytes());
    unsafe { str::from_utf8_unchecked(&out).to_string() }
}

// https://github.com/danreeves/path-clean/blob/master/src/lib.rs
fn clean_internal(path: &[u8]) -> Pod<u8> {
    static DOT: u8 = b'.';

    if path.is_empty() {
        return pod![DOT];
    }

    let rooted = path[0] == PATH_SEP;
    let n = path.len();

    // Invariants:
    //  - reading from path; r is index of next byte to process.
    //  - dotdot is index in out where .. must stop, either because it is the
    //    leading slash or it is a leading ../../.. prefix.
    //
    // The go code this function is based on handles already-clean paths without
    // an allocation, but I haven't done that here because I think it
    // complicates the return signature too much.
    let mut out: Pod<u8> = Pod::with_capacity(n);
    let mut r = 0;
    let mut dotdot = 0;

    if rooted {
        out.push(PATH_SEP);
        r = 1;
        dotdot = 1
    }

    while r < n {
        if path[r] == PATH_SEP || path[r] == DOT && (r + 1 == n || path[r + 1] == PATH_SEP) {
            // empty path element || . element: skip
            r += 1;
        } else if path[r] == DOT && path[r + 1] == DOT && (r + 2 == n || path[r + 2] == PATH_SEP) {
            // .. element: remove to last separator
            r += 2;
            if out.len() > dotdot {
                // can backtrack, truncate to last separator
                let mut w = out.len() - 1;
                while w > dotdot && out[w] != PATH_SEP {
                    w -= 1;
                }
                out.truncate(w);
            } else if !rooted {
                // cannot backtrack, but not rooted, so append .. element
                if !out.is_empty() {
                    out.push(PATH_SEP);
                }
                out.push(DOT);
                out.push(DOT);
                dotdot = out.len();
            }
        } else {
            // real path element
            // add slash if needed
            if rooted && out.len() != 1 || !rooted && !out.is_empty() {
                out.push(PATH_SEP);
            }
            while r < n && path[r] != PATH_SEP {
                out.push(path[r]);
                r += 1;
            }
        }
    }

    // Turn empty string into "."
    if out.is_empty() {
        out.push(DOT);
    }
    out
}

/// The column index at the given byte index in the source file.
/// This is the number of characters to the given byte index.
///
/// If the byte index is smaller than the start of the line, then `0` is returned.
/// If the byte index is past the end of the line, the column index of the last
/// character `+ 1` is returned.
pub fn column_index(source: &str, line_range: core::ops::Range<usize>, byte_index: usize) -> usize {
    let end_index = core::cmp::min(byte_index, core::cmp::min(line_range.end, source.len()));

    (line_range.start..end_index)
        .filter(|byte_index| source.is_char_boundary(byte_index + 1))
        .count()
}

static VALUE_ORDERING: AtomicU32 = AtomicU32::new(0);

pub fn uuid() -> u32 {
    return VALUE_ORDERING.fetch_add(1, Ordering::Relaxed);
}
