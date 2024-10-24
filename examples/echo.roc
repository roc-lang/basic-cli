app [main!] { pf: platform "../platform/main.roc" }

#import pf.Stdin
import pf.Stdout

main! = \{} ->
    Stdout.line!? "Shout into this cave and hear the echo!"
    Stdout.line! "Shout into this cave and hear the echo!"

    #loop! {} tick!

#tick! : {} => Result [Step {}, Done {}] _
#tick! = \{} ->
#    #result = Stdin.line! {}
#    Ok (Done {})
#    #when result is
#    #    Ok str ->
#    #        Stdout.line!? (echo str)
#    #        Ok (Step {})

#    #    Err (StdinErr EndOfFile) ->
#    #        Stdout.line! (echo "Received end of input (EOF).")
#    #        Ok (Done {})

#    #    Err (StdinErr err) ->
#    #        Stdout.line! (echo "Unable to read input $(Inspect.toStr err)")
#    #        Ok (Done {})

#echo : Str -> Str
#echo = \shout ->
#    silence = \length ->
#        List.repeat ' ' length

#    shout
#    |> Str.toUtf8
#    |> List.mapWithIndex
#        (\_, i ->
#            length = (List.len (Str.toUtf8 shout) - i)
#            phrase = (List.split (Str.toUtf8 shout) length).before

#            List.concat (silence (if i == 0 then 2 * length else length)) phrase)
#    |> List.join
#    |> Str.fromUtf8
#    |> Result.withDefault ""

#expect
#    message = "hello!"
#    echoedMessage = echo message

#    echoedMessage == "            hello!     hello    hell   hel  he h"

#loop! : state, (state => Result [Done done, Step state] err) => Result done err
#loop! = \state, stepFn! ->
#    result = stepFn! state
#    when result is
#        Ok (Step next) -> loop! next stepFn!
#        Ok (Done done) -> Ok done
#        Err err -> Err err
