app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout

# Example demonstrating the new Encode module with static dispatch
# Based on: https://github.com/roc-lang/roc/commit/22cf61ff9332f0de7a0d5d7f42b7f5836232a744
#
# The Encode module uses static dispatch via where clauses:
# - Str.encode requires: where [fmt.encode_str : fmt, Str -> List(U8)]
# - List.encode requires: where [fmt.encode_list : fmt, List(item), (item, fmt -> List(U8)) -> List(U8)]

# Define a custom JSON-like format type with the required methods
JsonFormat := [Format].{
    # Method required by Str.encode where clause
    encode_str : JsonFormat, Str -> List(U8)
    encode_str = |_fmt, str| {
        # Wrap string in quotes and convert to bytes
        quoted = "\"${str}\""
        Str.to_utf8(quoted)
    }

    # Method required by List.encode where clause  
    encode_list : JsonFormat, List(item), (item, JsonFormat -> List(U8)) -> List(U8)
    encode_list = |fmt, items, encode_item| {
        var $result = ['[']
        var $first = Bool.True
        
        for item in items {
            if $first {
                $first = Bool.False
            } else {
                $result = $result.append(',')
            }
            encoded_item = encode_item(item, fmt)
            $result = $result.concat(encoded_item)
        }
        
        $result.append(']')
    }
}

# Define a Person type that can be encoded as a JSON object
Person := [Person({ name : Str, age : U64 })].{
    # Custom encode method for Person - encodes as JSON object
    encode : Person, JsonFormat -> List(U8)
    encode = |self, fmt| {
        # Get the inner record via pattern match
        match self {
            Person({ name, age }) => {
                # Encode name as JSON string
                name_bytes = name.encode(fmt)
                
                # Encode age as number (no quotes)
                age_bytes = Str.to_utf8(age.to_str())
                
                # Build: {"name":"...","age":...}
                var $result = Str.to_utf8("{\"name\":")
                $result = $result.concat(name_bytes)
                $result = $result.concat(Str.to_utf8(",\"age\":"))
                $result = $result.concat(age_bytes)
                $result = $result.concat(Str.to_utf8("}"))
                $result
            }
        }
    }
}

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
    # Create our format instance using the tag constructor
    json_fmt = JsonFormat.Format
    
    # Encode a string using static dispatch
    # This calls Str.encode which requires fmt.encode_str
    hello_str = "Hello, World!"
    encoded_str = hello_str.encode(json_fmt)
    
    Stdout.line!("Encoded string:")
    Stdout.line!("  Input: ${hello_str}")
    
    # Convert back to string to show the JSON format
    match Str.from_utf8(encoded_str) {
        Ok(json_str) => Stdout.line!("  As JSON: ${json_str}")
        Err(_) => Stdout.line!("  (invalid UTF-8)")
    }
    
    Stdout.line!("")
    
    # Encode a list of strings using static dispatch
    # This calls List.encode which requires fmt.encode_list and item.encode
    names = ["Alice", "Bob", "Charlie"]
    encoded_list = names.encode(json_fmt)
    
    Stdout.line!("Encoded list of strings:")
    Stdout.line!("  Input: [\"Alice\", \"Bob\", \"Charlie\"]")
    
    match Str.from_utf8(encoded_list) {
        Ok(json_str) => Stdout.line!("  As JSON: ${json_str}")
        Err(_) => Stdout.line!("  (invalid UTF-8)")
    }
    
    Stdout.line!("")
    
    # Encode a Person as a JSON object
    alice : Person
    alice = Person.Person({ name: "Alice", age: 30 })
    person_bytes = alice.encode(json_fmt)
    
    Stdout.line!("Encoded Person object:")
    Stdout.line!("  Input: { name: \"Alice\", age: 30 }")
    
    match Str.from_utf8(person_bytes) {
        Ok(json_str) => Stdout.line!("  As JSON: ${json_str}")
        Err(_) => Stdout.line!("  (invalid UTF-8)")
    }
    
    Stdout.line!("")
    
    # Encode a list of Person objects
    people : List(Person)
    people = [
        Person.Person({ name: "Alice", age: 30 }),
        Person.Person({ name: "Bob", age: 25 }),
        Person.Person({ name: "Charlie", age: 35 }),
    ]
    people_bytes = people.encode(json_fmt)
    
    Stdout.line!("Encoded list of Person objects:")
    Stdout.line!("  Input: [{ name: \"Alice\", age: 30 }, { name: \"Bob\", age: 25 }, { name: \"Charlie\", age: 35 }]")
    
    match Str.from_utf8(people_bytes) {
        Ok(json_str) => Stdout.line!("  As JSON: ${json_str}")
        Err(_) => Stdout.line!("  (invalid UTF-8)")
    }
    
    Ok({})
}
