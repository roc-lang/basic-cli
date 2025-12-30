# Encode Module with Static Dispatch

This document explains the new `Encode` pattern in Roc using static dispatch via `where` clauses, based on [this commit](https://github.com/roc-lang/roc/commit/22cf61ff9332f0de7a0d5d7f42b7f5836232a744).

## Overview

The Encode module enables serializing values to bytes using **static dispatch** instead of the old Abilities system. Users define custom format types with specific methods, and the compiler resolves method calls at compile time.

## How It Works

### 1. Builtin Methods with `where` Clauses

The builtins define `encode` methods on `Str` and `List` with `where` clauses that require the format type to have specific methods:

```roc
# In Str (builtin)
encode : Str, fmt -> List(U8)
    where [fmt.encode_str : fmt, Str -> List(U8)]
encode = |self, format| {
    Fmt : fmt
    Fmt.encode_str(format, self)
}

# In List (builtin)
encode : List(item), fmt -> List(U8)
    where [
        fmt.encode_list : fmt, List(item), (item, fmt -> List(U8)) -> List(U8),
        item.encode : item, fmt -> List(U8)
    ]
encode = |self, format| {
    Fmt : fmt
    Item : item
    Fmt.encode_list(format, self, |elem, f| Item.encode(elem, f))
}
```

### 2. Define a Custom Format Type

To use `Str.encode` or `List.encode`, you define a nominal type with the required methods:

```roc
JsonFormat := [Format].{
    # Required by Str.encode
    encode_str : JsonFormat, Str -> List(U8)
    encode_str = |_fmt, str| {
        quoted = "\"${str}\""
        Str.to_utf8(quoted)
    }

    # Required by List.encode
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
```

Key points:
- `JsonFormat := [Format].{...}` defines a nominal type wrapping a tag union `[Format]`
- Methods are defined inside the `.{...}` block
- `encode_str` handles string encoding
- `encode_list` handles list encoding, receiving a callback to encode each item

### 3. Create a Format Instance

Construct the format using the tag constructor:

```roc
json_fmt = JsonFormat.Format
```

### 4. Encode Values

Call `.encode()` on strings or lists:

```roc
# Encode a string
hello_str = "Hello, World!"
encoded_str = hello_str.encode(json_fmt)
# Result: [34, 72, 101, 108, 108, 111, ...] (UTF-8 bytes of "Hello, World!")

# Encode a list of strings
names = ["Alice", "Bob", "Charlie"]
encoded_list = names.encode(json_fmt)
# Result: UTF-8 bytes of ["Alice","Bob","Charlie"]
```

### 5. Convert Back to String

```roc
match Str.from_utf8(encoded_str) {
    Ok(json_str) => Stdout.line!("As JSON: ${json_str}")
    Err(_) => Stdout.line!("(invalid UTF-8)")
}
```

## Complete Example

```roc
app [main!] { pf: platform "../platform/main.roc" }

import pf.Stdout

# Define a custom JSON-like format type with the required methods
JsonFormat := [Format].{
    encode_str : JsonFormat, Str -> List(U8)
    encode_str = |_fmt, str| {
        quoted = "\"${str}\""
        Str.to_utf8(quoted)
    }

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

main! : List(Str) => Try({}, [Exit(I32)])
main! = |_args| {
    json_fmt = JsonFormat.Format
    
    # Encode a string
    hello_str = "Hello, World!"
    encoded_str = hello_str.encode(json_fmt)
    
    Stdout.line!("Encoded string:")
    match Str.from_utf8(encoded_str) {
        Ok(json_str) => Stdout.line!("  ${json_str}")
        Err(_) => Stdout.line!("  (invalid UTF-8)")
    }
    
    # Encode a list of strings
    names = ["Alice", "Bob", "Charlie"]
    encoded_list = names.encode(json_fmt)
    
    Stdout.line!("Encoded list:")
    match Str.from_utf8(encoded_list) {
        Ok(json_str) => Stdout.line!("  ${json_str}")
        Err(_) => Stdout.line!("  (invalid UTF-8)")
    }
    
    Ok({})
}
```

## Output

```
Encoded string:
  "Hello, World!"
Encoded list:
  ["Alice","Bob","Charlie"]
```

## Static Dispatch Pattern

The key insight is that `where` clauses enable **ad-hoc polymorphism**:

1. A function declares what methods it needs via `where [type.method : signature]`
2. Any type that has those methods can be used
3. The compiler resolves the correct method at compile time (static dispatch)
4. No runtime overhead from dynamic dispatch

This replaces the old Abilities system with a simpler, more flexible pattern.
