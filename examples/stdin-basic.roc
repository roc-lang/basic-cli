app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdin
import pf.Stdout

main! = |_args| {
    match Stdout.line!("What's your first name?") { _ => {} }
    first = match Stdin.line!({}) {
        Ok(line) => line
        Err(_) => ""
    }

    match Stdout.line!("What's your last name?") { _ => {} }
    last = match Stdin.line!({}) {
        Ok(line) => line
        Err(_) => ""
    }

    match Stdout.line!("Hi, ${first} ${last}! \u(1F44B)") { _ => {} }
    Ok({})
}
