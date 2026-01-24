app [main!] { pf: platform "./platform/main.roc" }

import pf.Cmd

main! = |_args| {
    # Test if static dispatch with . works
    _cmd = Cmd.new("ls").arg("-l").args(["-a", "-h"])

    Ok({})
}
