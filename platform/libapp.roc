app [main] { pf: platform "main.roc" }

# Throw an error here so we can easily confirm the host
# executable built correctly just by running it.
#
# e.g.
# ```
# $ ./target/debug/host
# Program exited early with error: JustAStub
# ```
main = \{} -> Err (JustAStub)
