app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Arg exposing [Arg]
import pf.File
import pf.Cmd
import pf.Env
import pf.Path
import pf.Sleep

# This script performs the following tasks:
# 1. Reads the file platform/main.roc and extracts the exposes list.
# 2. For each module in the exposes list, it reads the corresponding file (e.g., platform/Path.roc) and extracts all functions in the module list.
# 3. Checks if each module.function is used in the examples or tests folder using ripgrep
# 4. Prints the functions that are not used anywhere in the examples or tests.

## For convenient string errors
err_s = |err_msg| Err(StrErr(err_msg))

main! : List Arg => Result {} _
main! = |_args|
    cwd = Env.cwd!({}) ? |err| FailedToGetCwd(err)
    Stdout.line!("Current working directory: ${Path.display(cwd)}")?

    path_to_platform_main = "platform/main.roc"

    main_content =
        File.read_utf8!(path_to_platform_main)?

    exposed_modules =
        extract_exposes_list(main_content)?

    # Uncomment for debugging
    # Stdout.line!("Found exposed modules: ${Str.join_with(exposed_modules, ", ")}")?

    module_name_and_functions = List.map_try!(
        exposed_modules,
        |module_name|
            process_module!(module_name),
    )?

    tagged_functions =
        module_name_and_functions
        |> List.map_try!(
            |{ module_name, exposed_functions }|
                List.map_try!(
                    exposed_functions,
                    |function_name|
                        if is_function_unused!(module_name, function_name)? then
                            Ok(NotFound("${module_name}.${function_name}"))
                        else
                            Ok(Found("${module_name}.${function_name}")),
                ),
        )?

    not_found_functions =
        tagged_functions
        |> List.join
        |> List.map(
            |tagged_function|
                when tagged_function is
                    Found _ -> ""
                    NotFound qualified_function_name -> qualified_function_name,
        )
        |> List.keep_if(|s| !Str.is_empty(s))

    if List.is_empty(not_found_functions) then
        Ok({})
    else
        Stdout.line!("Functions not used in basic-cli/examples or basic-cli/tests:")?
        List.for_each_try!(
            not_found_functions,
            |function_name|
                Stdout.line!(function_name),
        )?

        # Sleep to fix print order
        Sleep.millis!(1000)
        Err(Exit(1, "I found untested functions, see above."))

is_function_unused! : Str, Str => Result Bool _
is_function_unused! = |module_name, function_name|
    function_pattern = "${module_name}.${function_name}"
    search_dirs = ["examples", "tests"]

    # Check current working directory
    cwd = Env.cwd!({}) ? |err| FailedToGetCwd2(err)

    # Check if directories exist
    List.for_each_try!(
        search_dirs,
        |search_dir|
            is_dir_res = File.is_dir!(search_dir)

            when is_dir_res is
                Ok is_dir ->
                    if !is_dir then
                        err_s("Error: Path '${search_dir}' inside ${Path.display(cwd)} is not a directory.")
                    else
                        Ok({})

                Err (PathErr NotFound) ->
                    err_s("Error: Directory '${search_dir}' does not exist in ${Path.display(cwd)}")
                Err err ->
                    err_s("Error checking directory '${search_dir}': ${Inspect.to_str(err)}")
    )?

    # Check if ripgrep is installed
    rg_check_cmd = Cmd.new("rg") |> Cmd.arg("--version")
    rg_check_output = Cmd.output!(rg_check_cmd)

    when rg_check_output.status is
        Ok(0) ->
                unused_in_dir =
                    search_dirs
                    |> List.map_try!( |search_dir|
                        # Skip searching if directory doesn't exist
                        dir_exists = File.is_dir!(search_dir)?
                        if !dir_exists then
                            Ok(Bool.true) # Consider unused if we can't search
                        else
                            # Use ripgrep to search for the function pattern
                            cmd =
                                Cmd.new("rg")
                                |> Cmd.arg("-q") # Quiet mode - we only care about exit code
                                |> Cmd.arg(function_pattern)
                                |> Cmd.arg(search_dir)

                            status_res = Cmd.status!(cmd)

                            # ripgrep returns status 0 if matches were found, 1 if no matches
                            when status_res is
                                Ok(0) -> Ok(Bool.false) # Function is used (not unused)
                                _ -> Ok(Bool.true)
                    )?

                unused_in_dir
                |> List.walk!(Bool.true, |state, is_unused_res| state && is_unused_res)
                |> Ok
        _ ->
            err_s("Error: ripgrep (rg) is not installed or not available in PATH. Please install ripgrep to use this script. Full output: ${Inspect.to_str(rg_check_output)}")



process_module! : Str => Result { module_name : Str, exposed_functions : List Str } _
process_module! = |module_name|
    module_path = "platform/${module_name}.roc"

    module_source_code =
        File.read_utf8!(module_path)?

    module_items =
        extract_module_list(module_source_code)?

    module_functions =
        module_items
        |> List.keep_if(starts_with_lowercase)

    Ok({ module_name, exposed_functions: module_functions })

expect
    input =
        """
        exposes [
            Path,
            File,
            Http
        ]
        """

    output =
        extract_exposes_list(input)

    output == Ok(["Path", "File", "Http"])

# extra comma
expect
    input =
        """
        exposes [
            Path,
            File,
            Http,
        ]
        """

    output = extract_exposes_list(input)

    output == Ok(["Path", "File", "Http"])

# single line
expect
    input = "exposes [Path, File, Http]"

    output = extract_exposes_list(input)

    output == Ok(["Path", "File", "Http"])

# empty list
expect
    input = "exposes []"

    output = extract_exposes_list(input)

    output == Ok([])

# multiple spaces
expect
    input = "exposes   [Path]"

    output = extract_exposes_list(input)

    output == Ok(["Path"])

extract_exposes_list : Str -> Result (List Str) _
extract_exposes_list = |source_code|

    when Str.split_first(source_code, "exposes") is
        Ok { after } ->
            trimmed_after = Str.trim(after)

            if Str.starts_with(trimmed_after, "[") then
                list_content = Str.replace_first(trimmed_after, "[", "")

                when Str.split_first(list_content, "]") is
                    Ok { before } ->
                        modules =
                            before
                            |> Str.split_on(",")
                            |> List.map(Str.trim)
                            |> List.keep_if(|s| !Str.is_empty(s))

                        Ok(modules)

                    Err _ ->
                        err_s("Could not find closing bracket for exposes list in source code:\n\t${source_code}")
            else
                err_s("Could not find opening bracket after 'exposes' in source code:\n\t${source_code}")

        Err _ ->
            err_s("Could not find exposes section in source_code:\n\t${source_code}")

expect
    input =
        """
        module [
            Path,
            display,
            from_str,
            IOErr
        ]
        """

    output = extract_module_list(input)

    output == Ok(["Path", "display", "from_str", "IOErr"])

# extra comma
expect
    input =
        """
        module [
            Path,
            display,
            from_str,
            IOErr,
        ]
        """

    output = extract_module_list(input)

    output == Ok(["Path", "display", "from_str", "IOErr"])

expect
    input =
        "module [Path, display, from_str, IOErr]"

    output = extract_module_list(input)

    output == Ok(["Path", "display", "from_str", "IOErr"])

expect
    input =
        "module []"

    output = extract_module_list(input)

    output == Ok([])

# with extra space
expect
    input =
        "module  [Path]"

    output = extract_module_list(input)

    output == Ok(["Path"])

extract_module_list : Str -> Result (List Str) _
extract_module_list = |source_code|

    when Str.split_first(source_code, "module") is
        Ok { after } ->
            trimmed_after = Str.trim(after)

            if Str.starts_with(trimmed_after, "[") then
                list_content = Str.replace_first(trimmed_after, "[", "")

                when Str.split_first(list_content, "]") is
                    Ok { before } ->
                        items =
                            before
                            |> Str.split_on(",")
                            |> List.map(Str.trim)
                            |> List.keep_if(|s| !Str.is_empty(s))

                        Ok(items)

                    Err _ ->
                        err_s("Could not find closing bracket for module list in source code:\n\t${source_code}")
            else
                err_s("Could not find opening bracket after 'module' in source code:\n\t${source_code}")

        Err _ ->
            err_s("Could not find module section in source_code:\n\t${source_code}")

expect starts_with_lowercase("hello") == Bool.true
expect starts_with_lowercase("Hello") == Bool.false
expect starts_with_lowercase("!hello") == Bool.false
expect starts_with_lowercase("") == Bool.false

starts_with_lowercase : Str -> Bool
starts_with_lowercase = |str|
    if Str.is_empty(str) then
        Bool.false
    else
        first_char_byte =
            str
            |> Str.to_utf8
            |> List.first
            |> impossible_err("We verified that the string is not empty")

        # ASCII lowercase letters range from 97 ('a') to 122 ('z')
        first_char_byte >= 97 and first_char_byte <= 122

impossible_err = |result, err_msg|
    when result is
        Ok something ->
            something

        Err err ->
            crash "This should have been impossible: ${err_msg}.\n\tError was: ${Inspect.to_str(err)}"
