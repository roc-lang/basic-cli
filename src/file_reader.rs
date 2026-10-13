//! Line, delimited and binary reads that share one buffered cursor.
//!
//! Every read reports the end of input as `None`, only once no data is left,
//! and can be repeated afterwards: a source that has grown yields data again.
use std::io::{self, BufRead, Read, Seek, SeekFrom};

fn buffer(count: u64) -> io::Result<Vec<u8>> {
    let size = usize::try_from(count)
        .ok()
        .filter(|&size| size <= isize::MAX as usize)
        .ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::OutOfMemory,
                "file read size cannot fit in memory",
            )
        })?;
    let mut bytes = Vec::new();
    bytes.try_reserve_exact(size).map_err(|_| {
        io::Error::new(
            io::ErrorKind::OutOfMemory,
            "could not reserve memory for file read",
        )
    })?;
    bytes.resize(size, 0);
    Ok(bytes)
}

/// Read at most `count` bytes with one successful `read`.
///
/// `None` is the end of input. Asking for zero bytes performs no I/O and
/// returns an empty buffer, which is data, not the end.
pub(crate) fn read_up_to(reader: &mut impl Read, count: u64) -> io::Result<Option<Vec<u8>>> {
    let mut bytes = buffer(count)?;
    if count == 0 {
        return Ok(Some(bytes));
    }
    loop {
        match reader.read(&mut bytes) {
            Ok(0) => return Ok(None),
            Ok(n) => {
                bytes.truncate(n);
                return Ok(Some(bytes));
            }
            Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
            Err(error) => return Err(error),
        }
    }
}

/// Read bytes through and including the next `delimiter`.
///
/// If the input ends first, the bytes before the end are returned without a
/// delimiter. `None` is the end of input: no byte was left to return.
pub(crate) fn read_until(reader: &mut impl BufRead, delimiter: u8) -> io::Result<Option<Vec<u8>>> {
    let mut bytes = Vec::new();
    Ok(match reader.read_until(delimiter, &mut bytes)? {
        0 => None,
        _ => Some(bytes),
    })
}

/// Read one line, without its `\n` terminator and without one `\r` before it.
///
/// A final unterminated line is a line, returned as it is. `None` is the end
/// of input; an empty line is `Some` of an empty buffer.
pub(crate) fn read_line(reader: &mut impl BufRead) -> io::Result<Option<Vec<u8>>> {
    Ok(read_until(reader, b'\n')?.map(|mut line| {
        if line.last() == Some(&b'\n') {
            line.pop();
            if line.last() == Some(&b'\r') {
                line.pop();
            }
        }
        line
    }))
}

pub(crate) fn read_exactly(reader: &mut impl Read, count: u64) -> io::Result<Vec<u8>> {
    let mut bytes = buffer(count)?;
    if count != 0 {
        reader.read_exact(&mut bytes)?;
    }
    Ok(bytes)
}

pub(crate) fn position(reader: &mut impl Seek) -> io::Result<u64> {
    reader.stream_position()
}

pub(crate) fn seek(reader: &mut impl Seek, from: SeekFrom) -> io::Result<u64> {
    reader.seek(from)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{BufReader, Cursor, Write};

    #[test]
    fn binary_reads_share_line_buffer_and_logical_position() {
        let mut reader = BufReader::with_capacity(8, Cursor::new(b"a\n\0\xff\x80xyz"));
        let line = read_until(&mut reader, b'\n').unwrap().unwrap();
        assert_eq!(line, b"a\n");
        assert_eq!(position(&mut reader).unwrap(), 2);
        let retained = read_up_to(&mut reader, 2).unwrap().unwrap();
        assert_eq!(retained, b"\0\xff");
        assert_eq!(seek(&mut reader, SeekFrom::Current(-1)).unwrap(), 3);
        assert_eq!(read_exactly(&mut reader, 3).unwrap(), b"\xff\x80x");
        assert_eq!(position(&mut reader).unwrap(), 6);
        assert_eq!(retained, b"\0\xff");
        assert_eq!(seek(&mut reader, SeekFrom::End(-2)).unwrap(), 6);
        assert_eq!(read_up_to(&mut reader, 10).unwrap().unwrap(), b"yz");
        assert_eq!(read_up_to(&mut reader, 10).unwrap(), None);
        assert_eq!(seek(&mut reader, SeekFrom::Start(0)).unwrap(), 0);
        assert_eq!(read_exactly(&mut reader, 2).unwrap(), b"a\n");
        assert_eq!(seek(&mut reader, SeekFrom::Start(100)).unwrap(), 100);
        assert_eq!(read_up_to(&mut reader, 1).unwrap(), None);
        assert_eq!(reader.get_ref().get_ref().len(), 8);
        assert!(seek(&mut reader, SeekFrom::End(-100)).is_err());
    }

    struct ShortReads {
        bytes: Cursor<Vec<u8>>,
        interrupt: bool,
        fail: bool,
        calls: usize,
    }

    #[test]
    fn large_binary_input_crosses_buffers_without_losing_bytes() {
        let expected: Vec<u8> = (0..131_073).map(|i| i as u8).collect();
        let mut reader = BufReader::with_capacity(7, Cursor::new(&expected));
        let mut actual = Vec::new();
        while let Some(chunk) = read_up_to(&mut reader, 65_536).unwrap() {
            assert!(!chunk.is_empty() && chunk.len() <= 65_536);
            actual.extend(chunk);
        }
        assert_eq!(actual, expected);
        seek(&mut reader, SeekFrom::Start(0)).unwrap();
        assert_eq!(
            read_exactly(&mut reader, expected.len() as u64).unwrap(),
            expected
        );
    }

    impl Read for ShortReads {
        fn read(&mut self, into: &mut [u8]) -> io::Result<usize> {
            self.calls += 1;
            if std::mem::take(&mut self.interrupt) {
                return Err(io::ErrorKind::Interrupted.into());
            }
            if self.fail {
                return Err(io::ErrorKind::PermissionDenied.into());
            }
            let len = into.len().min(2);
            self.bytes.read(&mut into[..len])
        }
    }

    #[test]
    fn short_reads_interruptions_eof_and_errors() {
        let mut reader = ShortReads {
            bytes: Cursor::new(vec![0, 255, 128, 1, 2, 3, 4]),
            interrupt: true,
            fail: false,
            calls: 0,
        };
        assert_eq!(read_up_to(&mut reader, 5).unwrap().unwrap(), [0, 255]);
        assert_eq!(reader.calls, 2);
        reader.interrupt = true;
        assert_eq!(read_exactly(&mut reader, 4).unwrap(), [128, 1, 2, 3]);
        assert_eq!(
            read_exactly(&mut reader, 2).unwrap_err().kind(),
            io::ErrorKind::UnexpectedEof
        );
        assert_eq!(read_up_to(&mut reader, 1).unwrap(), None);
        reader.fail = true;
        assert_eq!(
            read_up_to(&mut reader, 1).unwrap_err().kind(),
            io::ErrorKind::PermissionDenied
        );
        assert_eq!(
            read_exactly(&mut reader, 1).unwrap_err().kind(),
            io::ErrorKind::PermissionDenied
        );
        let calls = reader.calls;
        assert_eq!(read_up_to(&mut reader, 0).unwrap(), Some(Vec::new()));
        assert!(read_exactly(&mut reader, 0).unwrap().is_empty());
        assert_eq!(
            read_up_to(&mut reader, u64::MAX).unwrap_err().kind(),
            io::ErrorKind::OutOfMemory
        );
        assert_eq!(
            read_exactly(&mut reader, u64::MAX).unwrap_err().kind(),
            io::ErrorKind::OutOfMemory
        );
        assert_eq!(reader.calls, calls);
    }

    fn lines(input: &[u8], capacity: usize) -> Vec<Vec<u8>> {
        let mut reader = BufReader::with_capacity(capacity, Cursor::new(input));
        let mut lines = Vec::new();
        while let Some(line) = read_line(&mut reader).unwrap() {
            lines.push(line);
        }
        // The end is reported again, not just once.
        assert_eq!(read_line(&mut reader).unwrap(), None);
        lines
    }

    #[test]
    fn lines_drop_the_terminator_and_one_carriage_return() {
        for capacity in [1, 2, 3, 64] {
            assert_eq!(
                lines(b"a\r\nb\n\nc", capacity),
                [&b"a"[..], b"b", b"", b"c"]
            );
            // Only one `\r` is removed, and only next to the terminator.
            assert_eq!(
                lines(b"a\r\r\n\rb\rc\n\r\n", capacity),
                [&b"a\r"[..], b"\rb\rc", b""]
            );
            // An unterminated last line is returned as it is.
            assert_eq!(lines(b"x\ny\r", capacity), [&b"x"[..], b"y\r"]);
            assert_eq!(lines(b"\n", capacity), [b""]);
            assert!(lines(b"", capacity).is_empty());
            // Bytes that are not UTF-8 are passed through for the caller to decode.
            assert_eq!(
                lines(b"ok\n\xff\xfe\r\nend\n", capacity),
                [&b"ok"[..], b"\xff\xfe", b"end"]
            );
        }
    }

    #[test]
    fn read_until_returns_the_delimiter_and_then_the_end() {
        let mut reader = BufReader::with_capacity(2, Cursor::new(b"ab|c||tail"));
        assert_eq!(read_until(&mut reader, b'|').unwrap().unwrap(), b"ab|");
        assert_eq!(read_until(&mut reader, b'|').unwrap().unwrap(), b"c|");
        assert_eq!(read_until(&mut reader, b'|').unwrap().unwrap(), b"|");
        // The input ends before another delimiter: the rest is data.
        assert_eq!(read_until(&mut reader, b'|').unwrap().unwrap(), b"tail");
        assert_eq!(read_until(&mut reader, b'|').unwrap(), None);
        assert_eq!(read_until(&mut reader, b'|').unwrap(), None);
        // Delimited reads share the cursor with the others.
        assert_eq!(seek(&mut reader, SeekFrom::Start(1)).unwrap(), 1);
        assert_eq!(read_until(&mut reader, b'c').unwrap().unwrap(), b"b|c");
        assert_eq!(read_exactly(&mut reader, 2).unwrap(), b"||");
        assert_eq!(position(&mut reader).unwrap(), 6);
        assert_eq!(read_line(&mut reader).unwrap().unwrap(), b"tail");
        assert_eq!(read_up_to(&mut reader, 4).unwrap(), None);
    }

    #[test]
    fn line_and_delimited_reads_report_errors_and_survive_interruptions() {
        let source = ShortReads {
            bytes: Cursor::new(b"one\r\ntwo".to_vec()),
            interrupt: true,
            fail: false,
            calls: 0,
        };
        let mut reader = BufReader::with_capacity(4, source);
        assert_eq!(read_line(&mut reader).unwrap().unwrap(), b"one");
        reader.get_mut().interrupt = true;
        assert_eq!(read_until(&mut reader, b'w').unwrap().unwrap(), b"tw");
        reader.get_mut().fail = true;
        // The buffered byte before the failure is consumed and lost.
        assert_eq!(
            read_line(&mut reader).unwrap_err().kind(),
            io::ErrorKind::PermissionDenied
        );
        assert_eq!(
            read_until(&mut reader, 0).unwrap_err().kind(),
            io::ErrorKind::PermissionDenied
        );
        // A failed source can be read again once it recovers.
        reader.get_mut().fail = false;
        assert_eq!(read_line(&mut reader).unwrap(), None);
    }

    #[test]
    fn reads_after_the_end_return_data_once_the_file_has_grown() {
        let path = std::env::temp_dir().join(format!(
            "basic-cli-file-reader-growth-{}.txt",
            std::process::id()
        ));
        let mut writer = std::fs::File::create(&path).unwrap();
        writer.write_all(b"first\npart").unwrap();
        writer.flush().unwrap();
        let mut reader = BufReader::new(std::fs::File::open(&path).unwrap());

        assert_eq!(read_line(&mut reader).unwrap().unwrap(), b"first");
        // The unterminated tail is returned before the end is reported.
        assert_eq!(read_until(&mut reader, b'\n').unwrap().unwrap(), b"part");
        assert_eq!(read_until(&mut reader, b'\n').unwrap(), None);
        assert_eq!(read_line(&mut reader).unwrap(), None);
        assert_eq!(read_up_to(&mut reader, 8).unwrap(), None);
        assert_eq!(
            read_exactly(&mut reader, 1).unwrap_err().kind(),
            io::ErrorKind::UnexpectedEof
        );

        writer.write_all(b"ial\r\nnext\nmore").unwrap();
        writer.flush().unwrap();
        assert_eq!(read_until(&mut reader, b'\n').unwrap().unwrap(), b"ial\r\n");
        assert_eq!(read_line(&mut reader).unwrap().unwrap(), b"next");
        assert_eq!(read_up_to(&mut reader, 2).unwrap().unwrap(), b"mo");
        assert_eq!(read_exactly(&mut reader, 2).unwrap(), b"re");
        assert_eq!(read_up_to(&mut reader, 2).unwrap(), None);

        writer.write_all(b"!").unwrap();
        writer.flush().unwrap();
        assert_eq!(read_up_to(&mut reader, 2).unwrap().unwrap(), b"!");
        assert_eq!(read_line(&mut reader).unwrap(), None);
        drop((reader, writer));
        std::fs::remove_file(&path).unwrap();
    }
}
