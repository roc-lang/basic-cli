app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Tcp
import pf.Arg exposing [Arg]

main! : List Arg => Result {} _
main! = |_args|
    Stdout.line!(
        """
        Testing Tcp module functions...
        Note: These tests require a TCP server running on localhost:8085
        You can start one with: ncat -e `which cat` -l 8085

        """
    )?

    Stdout.line!("Testing Tcp.connect!:")?
    when Tcp.connect!("127.0.0.1", 8085) is
        Ok(stream) ->
            Stdout.line!("✓ Successfully connected to localhost:8085")?
            test_tcp_functions!(stream)?
            Stdout.line!("\nAll tests executed.")
        
        Err(connect_err) ->
            err_str = Tcp.connect_err_to_str(connect_err)
            Err(Exit(1, "✗ Failed to connect: ${err_str}"))


test_tcp_functions! : Tcp.Stream => Result {} _
test_tcp_functions! = |stream|

    Stdout.line!("\nTesting Tcp.write!:")?
    hello_bytes = [72, 101, 108, 108, 111, 10] # "Hello\n" in bytes
    Tcp.write!(stream, hello_bytes)?

    reply_msg = Tcp.read_line!(stream)?
    Stdout.line!(
        """
        Echo server reply: ${reply_msg}


        Testing Tcp.write_utf8!:
        """
    )?
    test_message = "Test message from Roc!\n"
    Tcp.write_utf8!(stream, test_message)?
    
    reply_msg_utf8 = Tcp.read_line!(stream)?
    Stdout.line!(
        """
        Echo server reply: ${reply_msg_utf8}


        Testing Tcp.read_up_to!:
        """
    )?

    do_not_read_bytes = [100, 111, 32, 110, 111, 116, 32, 114, 101, 97, 100, 32, 112, 97, 115, 116, 32, 109, 101, 65] # "do not read past meA" in bytes
    Tcp.write!(stream, do_not_read_bytes)?

    nineteen_bytes = Tcp.read_up_to!(stream, 19) ? |err| FailedReadUpTo(err)
    nineteen_bytes_as_str = Str.from_utf8(nineteen_bytes) ? |err| ReadUpToFromUtf8(err)

    Stdout.line!(
        """
        Tcp.read_up_to yielded: '${nineteen_bytes_as_str}'


        Testing Tcp.read_exactly!:
        """
    )?
    Tcp.write_utf8!(stream, "BC")?

    three_bytes = Tcp.read_exactly!(stream, 3) ? |err| FailedReadExactly(err)
    three_bytes_as_str = Str.from_utf8(three_bytes) ? |err| ReadExactlyFromUtf8(err)

    Stdout.line!(
        """
        Tcp.read_exactly yielded: '${three_bytes_as_str}'


        Testing Tcp.read_until!:
        """
    )?
    Tcp.write_utf8!(stream, "Line1\nLine2\n")?

    bytes_until = Tcp.read_until!(stream, '\n') ? |err| FailedReadUntil(err)
    bytes_until_as_str = Str.from_utf8(bytes_until) ? |err| ReadUntilFromUtf8(err)

    Stdout.line!("Tcp.read_until yielded: '${bytes_until_as_str}'")?

    Ok({})