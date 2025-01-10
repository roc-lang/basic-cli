app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Stderr
import pf.Stdin

# To run this example: check the README.md in this folder

main! = \_args ->
    Stdout.line!("Enter a series of number characters (0-9):")?

    number_bytes = take_number_bytes!({})?

    if List.is_empty(number_bytes) then
        Stderr.line!("Expected a series of number characters (0-9)")
    else
        when Str.from_utf8(number_bytes) is
            Ok(n_str) ->
                Stdout.line!("Got number $(n_str)")

            Err(_) ->
                Stderr.line!("Error, bad utf8")

take_number_bytes! : {} => Result (List U8) _
take_number_bytes! = \{} ->
    bytes_read = Stdin.bytes!({})?

    number_bytes =
        List.walk(
            bytes_read,
            [],
            \bytes, b ->
                if b >= '0' && b <= '9' then
                    List.append(bytes, b)
                else
                    bytes,
        )

    Ok(number_bytes)
