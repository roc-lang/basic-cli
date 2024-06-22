module [strLen, isKebabCase, toUpperCase]

lowerAAsciiCode = 97
lowerZAsciiCode = 122
lowerToUpperCaseAsciiDelta = 32

# TODO: this is a terrible way to check string length!
strLen : Str -> U64
strLen = \s -> List.len (Str.toUtf8 s)

isDigit : U8 -> Bool
isDigit = \char ->
    zeroAsciiCode = 48
    nineAsciiCode = 57

    char >= zeroAsciiCode && char <= nineAsciiCode

isLowerCase : U8 -> Bool
isLowerCase = \char ->
    char >= lowerAAsciiCode && char <= lowerZAsciiCode

isKebabCase : Str -> Bool
isKebabCase = \s ->
    dashAsciiCode : U8
    dashAsciiCode = 45

    when Str.toUtf8 s is
        [] -> Bool.false
        [single] -> isLowerCase single || isDigit single
        [first, .. as middle, last] ->
            firstIsKebab = isLowerCase first
            lastIsKebab = isLowerCase last || isDigit last
            middleIsKebab =
                middle
                |> List.all \char ->
                    isLowerCase char || isDigit char || char == dashAsciiCode
            noDoubleDashes =
                middle
                |> List.map2 (List.dropFirst middle 1) Pair
                |> List.all \Pair left right ->
                    !(left == dashAsciiCode && right == dashAsciiCode)

            firstIsKebab && lastIsKebab && middleIsKebab && noDoubleDashes

toUpperCase : Str -> Str
toUpperCase = \str ->
    str
    |> Str.toUtf8
    |> List.map \c ->
        if isLowerCase c then
            c - lowerToUpperCaseAsciiDelta
        else
            c
    |> Str.fromUtf8
    |> Result.withDefault ""

expect strLen "123" == 3

expect
    sample = "19aB "

    sample
    |> Str.toUtf8
    |> List.map isDigit
    == [Bool.true, Bool.true, Bool.false, Bool.false, Bool.false]

expect
    sample = "aAzZ-"

    sample
    |> Str.toUtf8
    |> List.map isLowerCase
    == [Bool.true, Bool.false, Bool.true, Bool.false, Bool.false]

expect isKebabCase "abc-def"
expect isKebabCase "-abc-def" |> Bool.not
expect isKebabCase "abc-def-" |> Bool.not
expect isKebabCase "-" |> Bool.not
expect isKebabCase "" |> Bool.not

expect toUpperCase "abc" == "ABC"
expect toUpperCase "ABC" == "ABC"
expect toUpperCase "aBc00-" == "ABC00-"
