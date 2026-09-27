//! Binary operations on the same buffered cursor used by line reads.
use std::io::{self, Read, Seek, SeekFrom};

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

pub(crate) fn read_up_to(reader: &mut impl Read, count: u64) -> io::Result<Vec<u8>> {
    let mut bytes = buffer(count)?;
    if count == 0 {
        return Ok(bytes);
    }
    loop {
        match reader.read(&mut bytes) {
            Ok(n) => {
                bytes.truncate(n);
                return Ok(bytes);
            }
            Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
            Err(error) => return Err(error),
        }
    }
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
    use std::io::{BufRead, BufReader, Cursor};

    #[test]
    fn binary_reads_share_line_buffer_and_logical_position() {
        let mut reader = BufReader::with_capacity(8, Cursor::new(b"a\n\0\xff\x80xyz"));
        let mut line = Vec::new();
        reader.read_until(b'\n', &mut line).unwrap();
        assert_eq!(line, b"a\n");
        assert_eq!(position(&mut reader).unwrap(), 2);
        let retained = read_up_to(&mut reader, 2).unwrap();
        assert_eq!(retained, b"\0\xff");
        assert_eq!(seek(&mut reader, SeekFrom::Current(-1)).unwrap(), 3);
        assert_eq!(read_exactly(&mut reader, 3).unwrap(), b"\xff\x80x");
        assert_eq!(position(&mut reader).unwrap(), 6);
        assert_eq!(retained, b"\0\xff");
        assert_eq!(seek(&mut reader, SeekFrom::End(-2)).unwrap(), 6);
        assert_eq!(read_up_to(&mut reader, 10).unwrap(), b"yz");
        assert!(read_up_to(&mut reader, 10).unwrap().is_empty());
        assert_eq!(seek(&mut reader, SeekFrom::Start(0)).unwrap(), 0);
        assert_eq!(read_exactly(&mut reader, 2).unwrap(), b"a\n");
        assert_eq!(seek(&mut reader, SeekFrom::Start(100)).unwrap(), 100);
        assert!(read_up_to(&mut reader, 1).unwrap().is_empty());
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
        loop {
            let chunk = read_up_to(&mut reader, 65_536).unwrap();
            assert!(chunk.len() <= 65_536);
            if chunk.is_empty() {
                break;
            }
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
        assert_eq!(read_up_to(&mut reader, 5).unwrap(), [0, 255]);
        assert_eq!(reader.calls, 2);
        reader.interrupt = true;
        assert_eq!(read_exactly(&mut reader, 4).unwrap(), [128, 1, 2, 3]);
        assert_eq!(
            read_exactly(&mut reader, 2).unwrap_err().kind(),
            io::ErrorKind::UnexpectedEof
        );
        assert!(read_up_to(&mut reader, 1).unwrap().is_empty());
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
        assert!(read_up_to(&mut reader, 0).unwrap().is_empty());
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
}
