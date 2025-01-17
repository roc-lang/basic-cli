app [main!] { pf: platform "main.roc" }

# Throw an error here so we can easily confirm the host
# executable built correctly just by running it.
main! : _ => Result {} [Exit I32 Str]_
main! = |_args|
    Err(JustAStub)
