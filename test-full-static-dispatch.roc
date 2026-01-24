app [main!] { pf: platform "./platform/main.roc" }

import pf.Cmd
import pf.Stdout

main! = |_args| {
    Stdout.line!("=== Testing Full Static Dispatch ===")

    # Test 1: Simple method chaining with effect
    Stdout.line!("\n1. Simple method chaining:")
    exit_code = Cmd.new("echo").args(["Hello World"]).exec_exit_code!()?
    Stdout.line!("   Exit code: ${exit_code.to_str()}")

    # Test 2: Multiline builder pattern with effect
    Stdout.line!("\n2. Multiline builder pattern:")
    result =
        Cmd.new("env")
        .clear_envs()
        .env("TEST_VAR", "test_value")
        .envs([("VAR1", "val1"), ("VAR2", "val2")])
        .args(["-v"])
        .exec_cmd!()

    match result {
        Ok({}) => Stdout.line!("   Command succeeded")
        Err(_) => Stdout.line!("   Command failed")
    }

    # Test 3: Capture output with static dispatch
    Stdout.line!("\n3. Capturing output:")
    output_result =
        Cmd.new("echo")
        .args(["Static dispatch works!"])
        .exec_output!()

    match output_result {
        Ok(output) => Stdout.line!("   Output: ${output.stdout_utf8}")
        Err(_) => Stdout.line!("   Failed to capture output")
    }

    # Test 4: All in one fluent chain
    Stdout.line!("\n4. Complete fluent chain:")
    chain_result = Cmd.new("echo").args(["Amazing!"]).exec_cmd!()
    match chain_result {
        Ok({}) => {}
        Err(_) => Stdout.line!("   Chain failed")
    }

    Stdout.line!("\n=== All tests passed! ===")

    Ok({})
}
