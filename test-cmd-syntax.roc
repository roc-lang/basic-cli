app [main!] { pf: platform "./platform/main.roc" }

import pf.Cmd

main! = |_args| {
    # Test new function call syntax with ->
    _cmd = Cmd.new("ls")->Cmd.arg("-l")->Cmd.args(["-a", "-h"])

    # Alternative: regular function call syntax (more verbose)
    _cmd3 = Cmd.arg(Cmd.new("ls"), "-l")

    # Multiline with ->
    _cmd4 =
        Cmd.new("echo")
        ->Cmd.args(["Hi"])

    Ok({})
}
