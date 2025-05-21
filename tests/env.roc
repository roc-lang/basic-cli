app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Env
import pf.Path
import pf.Arg exposing [Arg]

main! : List Arg => Result {} _
main! = |_args|
    Stdout.line!("Testing Env module functions...")?

    Stdout.line!("\nTesting Env.cwd!:")?
    cwd = Env.cwd!({})?
    Stdout.line!("cwd: ${Inspect.to_str(cwd)}")?

    Stdout.line!("\nTesting Env.exe_path!:")?
    exe_path = Env.exe_path!({})?
    Stdout.line!("exe_path: ${Inspect.to_str(exe_path)}")?

    # Test Env.platform!
    Stdout.line!("\nTesting Env.platform!:")?
    platform = Env.platform!({})
    Stdout.line!("Current platform:${Inspect.to_str(platform)}")?

    # Test Env.dict!
    Stdout.line!("\nTesting Env.dict!:")?
    env_vars = Env.dict!({})
    var_count = Dict.len(env_vars)
    Stdout.line!("Environment variables count: ${Num.to_str(var_count)}")?
    
    some_env_vars = Dict.to_list(env_vars) |> List.take_first(3)
    Stdout.line!("Sample environment variables:${Inspect.to_str(some_env_vars)}")?

    # Test Env.set_cwd!
    Stdout.line!("\nTesting Env.set_cwd!:")?
    
    # First get the current directory to restore it later
    original_dir = Env.cwd!({})?
    ls_list = Path.list_dir!(original_dir)?

    dir_list =
        ls_list
        |> List.keep_if_try!(|path| Path.is_dir!(path))?

    first_dir =
        List.first(dir_list)?

    Env.set_cwd!(first_dir)?
    new_cwd = Env.cwd!({})?
    Stdout.line!("Changed current directory to: ${Inspect.to_str(new_cwd)}")?

    Stdout.line!("\nAll tests executed!")?

    Ok({})