app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Arg exposing [Arg]
import pf.File
import pf.Env
import pf.Path

# This script performs the following tasks:
# 1. Reads Cargo.toml and ci/rust_http_server/Cargo.toml files
# 2. Extracts dependencies from both files
# 3. Compares versions of dependencies that exist in both files
# 4. Reports any version mismatches

## For convenient string errors
err_s = |err_msg| Err(StrErr(err_msg))

err_exit = |err_msg| Err(Exit(1, "\n❌ ${err_msg}"))

main! : List Arg => Result {} _
main! = |_args|
    cwd = Env.cwd!({}) ? |err| FailedToGetCwd(err)
    Stdout.line!("Current working directory: ${Path.display(cwd)}")?

    root_cargo_path = "Cargo.toml"
    ci_cargo_path = "ci/rust_http_server/Cargo.toml"

    # Check if both files exist
    root_exists = File.is_file!(root_cargo_path)?
    ci_exists = File.is_file!(ci_cargo_path)?

    if !root_exists then
        err_exit("${root_cargo_path} not found in ${Path.display(cwd)}.")
    else if !ci_exists then
        err_exit("${ci_cargo_path} not found in ${Path.display(cwd)}.")
    else
        # Read both Cargo.toml files
        root_content = File.read_utf8!(root_cargo_path)?
        ci_content = File.read_utf8!(ci_cargo_path)?

        root_deps = extract_dependencies(root_content)
        expect !List.is_empty(root_deps)

        ci_deps = extract_dependencies(ci_content)
        expect !List.is_empty(ci_deps)

        mismatches = find_version_mismatches(root_deps, ci_deps)

        if List.is_empty(mismatches) then
            Stdout.line!("✓ All shared dependencies have matching versions")
        else
            all_mistmatches_str = 
                mismatches
                |> List.map(
                    |{ dep_name, root_version, ci_version }|
                        "  ${dep_name}: ${root_cargo_path} has '${root_version}', ${ci_cargo_path} has '${ci_version}'"
                )
                |> Str.join_with("\n")

            err_exit("Found version mismatches in shared dependencies:\n\n${all_mistmatches_str}")

# test find_version_mismatches
expect
    root_deps = [
        { name: "serde", version: "1.0" },
        { name: "tokio", version: "1.0" },
        { name: "unique_to_root", version: "2.0" },
    ]

    ci_deps = [
        { name: "serde", version: "1.0" },
        { name: "tokio", version: "1.0.1" },
        { name: "unique_to_ci", version: "3.0" },
    ]

    mismatches = find_version_mismatches(root_deps, ci_deps)

    expected = [
        { dep_name: "tokio", root_version: "1.0", ci_version: "1.0.1" },
    ]

    mismatches == expected

find_version_mismatches : List { name : Str, version : Str }, List { name : Str, version : Str } -> List { dep_name : Str, root_version : Str, ci_version : Str }
find_version_mismatches = |root_deps, ci_deps|
    root_deps
    |> List.walk(
        [],
        |state, root_dep|
            # Find matching dependency in CI cargo file
            when List.find_first(ci_deps, |ci_dep| ci_dep.name == root_dep.name) is
                Ok ci_dep ->
                    if root_dep.version != ci_dep.version then
                        List.append(state, { dep_name: root_dep.name, root_version: root_dep.version, ci_version: ci_dep.version })
                    else
                        state # Versions match, no mismatch

                Err _ ->
                    state # Dependency not found in CI file, not a shared dependency
    )

# test extract_dependencies
expect
    input =
        """
        [dependencies]
        serde = { version = "1.0.0", features = ["derive"] }
        tokio = { version = "1.0", default-features = false }
        """

    output = extract_dependencies(input)

    expected = [
        { name: "serde", version: "1.0.0" },
        { name: "tokio", version: "1.0" },
    ]

    output == expected

extract_dependencies : Str -> (List { name : Str, version : Str })
extract_dependencies = |toml_content|
    lines = Str.split_on(toml_content, "\n")

    final_state = List.walk(
        lines,
        { deps: [], in_dep_section: Bool.false },
        |state, line|
            trimmed_line = Str.trim(line)

            # Check if we're entering a dependency section
            is_dep_section = Str.contains(trimmed_line, "dependencies]")

            # Check if we're entering a different section (starts with [ but not a dependency section)
            is_other_section = 
                Str.starts_with(trimmed_line, "[") 
                && !is_dep_section 
                && !Str.is_empty(trimmed_line)

            new_in_dep_section = 
                if is_dep_section then
                    Bool.true
                else if is_other_section then
                    Bool.false
                else
                    state.in_dep_section

            if state.in_dep_section && !Str.is_empty(trimmed_line) && !Str.starts_with(trimmed_line, "[") then
                # Parse dependency line
                when parse_dependency_line(trimmed_line) is
                    Ok dep ->
                        { deps: List.append(state.deps, dep), in_dep_section: new_in_dep_section }

                    Err _ ->
                        # Skip lines that don't parse as dependencies (like comments)
                        { state & in_dep_section: new_in_dep_section }
            else
                { state & in_dep_section: new_in_dep_section }
    )

    final_state.deps


# test parse_dependency_line
expect
    input2 = "tokio = { version = \"1.0\", features = [\"full\"] }"
    output2 = parse_dependency_line(input2)
    output2 == Ok({ name: "tokio", version: "1.0" })

parse_dependency_line : Str -> Result { name : Str, version : Str } _
parse_dependency_line = |line|
    trimmed = Str.trim(line)

    # Skip comments and empty lines
    if Str.starts_with(trimmed, "#") || Str.is_empty(trimmed) then
        err_s("I expected a dependency line like 'dep = \"1.0\"', but got '${trimmed}'.")
    else
        { before: name_part, after: value_part } = Str.split_first(trimmed, "=") ? |_| err_s("I expected a `=` in this line: '${trimmed}'")

        dep_name = Str.trim(name_part)
        trimmed_value = Str.trim(value_part)

        version = 
            if Str.starts_with(trimmed_value, "\"") then
                # Simple version string like "1.0"
                extract_quoted_string(trimmed_value)?
            else if Str.starts_with(trimmed_value, "{") then
                # Table format like { version = "1.0", features = [...] }
                extract_version_from_table(trimmed_value)?
            else
                err_s("I don't recognize this dependency format: ${trimmed_value}")?

        Ok({ name: dep_name, version })

# test extract_quoted_string
expect
    input1 = "\"1.0\""
    output1 = extract_quoted_string(input1)
    output1 == Ok("1.0")

extract_quoted_string : Str -> Result Str _
extract_quoted_string = |str|
    if Str.starts_with(str, "\"") && Str.ends_with(str, "\"") then
        # Remove first and last character (the quotes)
        inner = 
            str
            |> Str.to_utf8
            |> List.drop_first(1)
            |> List.drop_last(1)
        
        Str.from_utf8(inner)
    else
        err_s("String is not properly quoted: ${str}")


# test extract_version_from_table
expect
    input2 = "{ version = \"1.0\", features = [\"full\"] }"
    output2 = extract_version_from_table(input2)
    output2 == Ok("1.0")

extract_version_from_table : Str -> Result Str _
extract_version_from_table = |table_str|
    # Find "version = " in the table
    { after } = Str.split_first(table_str, "version") ? |_| err_s("Could not find substring 'version' in table: ${table_str}")
    
    # Look for the equals sign
    trimmed_after = Str.trim(after)
    
    if Str.starts_with(trimmed_after, "=") then
        value_part = 
            trimmed_after
            |> Str.to_utf8
            |> List.drop_first(1)
            |> Str.from_utf8?
            |> Str.trim
        # Find the quoted version string
        { after: after_first_quote } = Str.split_first(value_part, "\"") ? |_| err_s("Could not find opening quote for version in: ${table_str}")
        { before: version_content } = Str.split_first(after_first_quote, "\"") ? |_| err_s("Could not find closing quote for version in: ${table_str}")

        Ok(version_content)
    else
        err_s("Could not find '=' after version in: ${table_str}")

# START extra extract_dependencies tests
expect
    input =
        """
        [dependencies]
        serde = "1.0"
        tokio = { version = "1.0", features = ["full"] }
        clap = "4.0"

        [dev-dependencies]
        criterion = "0.5"
        """

    output = extract_dependencies(input)

    expected = [
        { name: "serde", version: "1.0" },
        { name: "tokio", version: "1.0" },
        { name: "clap", version: "4.0" },
        { name: "criterion", version: "0.5" },
    ]

    output == expected
    
expect
    input =
        """
        [workspace.dependencies]
        simple-dep = "1.0"
        """

    output = extract_dependencies(input)

    expected = [
        { name: "simple-dep", version: "1.0" },
    ]

    output == expected

expect
    input = "[dependencies]"

    output = extract_dependencies(input)

    output == []

# END extra extract_dependencies tests

# START extra parse_dependency_line tests

expect
    input1 = "serde = \"1.0\""
    output1 = parse_dependency_line(input1)
    output1 == Ok({ name: "serde", version: "1.0" })
    
expect
    input3 = "clap = { version = \"4.0\" }"
    output3 = parse_dependency_line(input3)
    output3 == Ok({ name: "clap", version: "4.0" })

expect
    input4 = "# this is a comment"
    output4 = parse_dependency_line(input4)
    when output4 is
        Err _ -> Bool.true
        Ok _ -> Bool.false

expect
    input5 = "invalid-line-without-equals"
    output5 = parse_dependency_line(input5)
    when output5 is
        Err _ -> Bool.true
        Ok _ -> Bool.false

# END extra parse_dependency_line tests

# START extra extract_quoted_string tests

expect
    input2 = "\"1.0.0\""
    output2 = extract_quoted_string(input2)
    output2 == Ok("1.0.0")

expect
    input3 = "1.0"
    output3 = extract_quoted_string(input3)
    when output3 is
        Err _ -> Bool.true
        Ok _ -> Bool.false

# END extra extract_quoted_string tests

# START extra extract_version_from_table tests

expect
    input1 = "{ version = \"1.0\" }"
    output1 = extract_version_from_table(input1)
    output1 == Ok("1.0")

expect
    input3 = "{ features = [\"full\"] }"
    output3 = extract_version_from_table(input3)
    when output3 is
        Err _ -> Bool.true
        Ok _ -> Bool.false

# END extra extract_version_from_table tests