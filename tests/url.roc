app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout
import pf.Url
import pf.Arg exposing [Arg]

main! : List Arg => Result {} _
main! = |_args|
    Stdout.line!("Testing Url module functions...")?

    # Need to split this up due to high memory consumption bug
    test_part_1!({})?
    test_part_2!({})?

    Stdout.line!("\nAll tests executed.")?

    Ok({})

test_part_1! : {} => Result {} _
test_part_1! = |{}|
    # Test Url.from_str and Url.to_str
    url = Url.from_str("https://example.com")
    Stdout.line!("Created URL: ${Url.to_str(url)}")?
    # expects "https://example.com"

    Stdout.line!("Testing Url.append:")?
    
    urlWithPath = Url.append(url, "some stuff")
    Stdout.line!("URL with append: ${Url.to_str(urlWithPath)}")?
    # expects "https://example.com/some%20stuff"
    
    url_search = Url.from_str("https://example.com?search=blah#fragment")
    url_search_append = Url.append(url_search, "stuff")
    Stdout.line!("URL with query and fragment, then appended path: ${Url.to_str(url_search_append)}")?
    # expects "https://example.com/stuff?search=blah#fragment"
    
    url_things = Url.from_str("https://example.com/things/")
    url_things_append = Url.append(url_things, "/stuff/")
    url_things_append_more = Url.append(url_things_append, "/more/etc/")
    Stdout.line!("URL with multiple appended paths: ${Url.to_str(url_things_append_more)}")?
    # expects "https://example.com/things/stuff/more/etc/")

    # Test Url.append_param
    Stdout.line!("Testing Url.append_param:")?
    
    url_example = Url.from_str("https://example.com")
    url_example_param = Url.append_param(url_example, "email", "someone@example.com")
    Stdout.line!("URL with appended param: ${Url.to_str(url_example_param)}")?
    # expects "https://example.com?email=someone%40example.com"
    
    url_example_2 = Url.from_str("https://example.com")
    url_example_2_cafe = Url.append_param(url_example_2, "café", "du Monde")
    url_example_2_cafe_email = Url.append_param(url_example_2_cafe, "email", "hi@example.com")
    Stdout.line!("URL with multiple appended params: ${Url.to_str(url_example_2_cafe_email)}")?
    # expects "https://example.com?caf%C3%A9=du%20Monde&email=hi%40example.com")?

    # Test Url.has_query
    Stdout.line!("\nTesting Url.has_query:")?
    
    url_with_query = Url.from_str("https://example.com?key=value#stuff")
    hasQuery1 = Url.has_query(url_with_query)
    Stdout.line!("URL with query has_query: ${Inspect.to_str(hasQuery1)}")?
    # expects Bool.true
    
    url_hashtag = Url.from_str("https://example.com#stuff")
    hasQuery2 = Url.has_query(url_hashtag)
    Stdout.line!("URL without query has_query: ${Inspect.to_str(hasQuery2)}")?
    # expects Bool.false

    Stdout.line!("\nTesting Url.has_fragment:")?
    
    url_key_val_hashtag = Url.from_str("https://example.com?key=value#stuff")
    has_fragment = Url.has_fragment(url_key_val_hashtag)
    Stdout.line!("URL with fragment has_fragment: ${Inspect.to_str(has_fragment)}")?
    # expects Bool.true
    
    url_key_val = Url.from_str("https://example.com?key=value")
    has_fragment_2 = Url.has_fragment(url_key_val)
    Stdout.line!("URL without fragment has_fragment: ${Inspect.to_str(has_fragment_2)}")?
    # expects Bool.false

    Stdout.line!("\nTesting Url.query:")?
    
    url_key_val_multi = Url.from_str("https://example.com?key1=val1&key2=val2&key3=val3#stuff")
    query = Url.query(url_key_val_multi)
    Stdout.line!("Query from URL: ${query}")?
    # expects "key1=val1&key2=val2&key3=val3"
    
    url_no_query = Url.from_str("https://example.com#stuff")
    query_empty = Url.query(url_no_query)
    Stdout.line!("Query from URL without query: ${query_empty}")
    # expects ""

test_part_2! : {} => Result {} _
test_part_2! = |{}|
    # Test Url.fragment
    Stdout.line!("\nTesting Url.fragment:")?
    
    url_with_fragment = Url.from_str("https://example.com#stuff")
    fragment = Url.fragment(url_with_fragment)
    Stdout.line!("Fragment from URL: ${fragment}")?
    # expects "stuff"
    
    url_no_fragment = Url.from_str("https://example.com")
    fragment_empty = Url.fragment(url_no_fragment)
    Stdout.line!("Fragment from URL without fragment: ${fragment_empty}")?
    # expects ""

    # Test Url.reserve
    Stdout.line!("\nTesting Url.reserve:")?
    
    url_to_reserve = Url.from_str("https://example.com")
    url_reserved = Url.reserve(url_to_reserve, 50)
    url_with_params = url_reserved
        |> Url.append("stuff")
        |> Url.append_param("café", "du Monde")
        |> Url.append_param("email", "hi@example.com")
    
    Stdout.line!("URL with reserved capacity and params: ${Url.to_str(url_with_params)}")?
    # expects "https://example.com/stuff?caf%C3%A9=du%20Monde&email=hi%40example.com"

    # Test Url.with_query
    Stdout.line!("\nTesting Url.with_query:")?
    
    url_replace_query = Url.from_str("https://example.com?key1=val1&key2=val2#stuff")
    url_with_new_query = Url.with_query(url_replace_query, "newQuery=thisRightHere")
    Stdout.line!("URL with replaced query: ${Url.to_str(url_with_new_query)}")?
    # expects "https://example.com?newQuery=thisRightHere#stuff"
    
    url_remove_query = Url.from_str("https://example.com?key1=val1&key2=val2#stuff")
    url_with_empty_query = Url.with_query(url_remove_query, "")
    Stdout.line!("URL with removed query: ${Url.to_str(url_with_empty_query)}")?
    # expects "https://example.com#stuff"

    # Test Url.with_fragment
    Stdout.line!("\nTesting Url.with_fragment:")?
    
    url_replace_fragment = Url.from_str("https://example.com#stuff")
    url_with_new_fragment = Url.with_fragment(url_replace_fragment, "things")
    Stdout.line!("URL with replaced fragment: ${Url.to_str(url_with_new_fragment)}")?
    # expects "https://example.com#things"
    
    url_add_fragment = Url.from_str("https://example.com")
    url_with_added_fragment = Url.with_fragment(url_add_fragment, "things")
    Stdout.line!("URL with added fragment: ${Url.to_str(url_with_added_fragment)}")?
    # expects "https://example.com#things"
    
    url_remove_fragment = Url.from_str("https://example.com#stuff")
    url_with_empty_fragment = Url.with_fragment(url_remove_fragment, "")
    Stdout.line!("URL with removed fragment: ${Url.to_str(url_with_empty_fragment)}")?
    # expects "https://example.com"

    # Test Url.query_params
    Stdout.line!("\nTesting Url.query_params:")?
    
    url_with_many_params = Url.from_str("https://example.com?key1=val1&key2=val2&key3=val3")
    params_dict = Url.query_params(url_with_many_params)
    
    # Check if params contains expected key-value pairs
    Stdout.line!("params_dict: ${Inspect.to_str(params_dict)}")?
    # expects Dict with key1=val1, key2=val2, key3=val3

    # Test Url.path
    Stdout.line!("\nTesting Url.path:")?
    
    url_with_path = Url.from_str("https://example.com/foo/bar?key1=val1&key2=val2#stuff")
    path = Url.path(url_with_path)
    Stdout.line!("Path from URL: ${path}")?
    # expects "example.com/foo/bar"
    
    url_relative = Url.from_str("/foo/bar?key1=val1&key2=val2#stuff")
    path_relative = Url.path(url_relative)
    Stdout.line!("Path from relative URL: ${path_relative}")?
    # expects "/foo/bar"

    Ok({})
