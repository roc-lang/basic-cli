interface Task
    exposes [
        Task,
        succeed,
        fail,
        await,
        map,
        mapFail,
        onFail,
        attempt,
        forever,
        loop,
        fromResult,
        batch,
    ]
    imports [Effect, InternalTask]

## A Task represents an effect; an interaction with state outside your Roc 
## program, such as the terminal's standard output, or a file.
Task ok err : InternalTask.Task ok err

## Run a task that never ends. Note that this task does not return a value.
forever : Task val err -> Task * err
forever = \task ->
    looper = \{} ->
        task
        |> InternalTask.toEffect
        |> Effect.map
            \res ->
                when res is
                    Ok _ -> Step {}
                    Err e -> Done (Err e)

    Effect.loop {} looper
    |> InternalTask.fromEffect

## Run a task repeatedly, until it fails with `err` or completes with `done`.
loop : state, (state -> Task [Step state, Done done] err) -> Task done err
loop = \state, step ->
    looper = \current ->
        step current
        |> InternalTask.toEffect
        |> Effect.map
            \res ->
                when res is
                    Ok (Step newState) -> Step newState
                    Ok (Done result) -> Done (Ok result)
                    Err e -> Done (Err e)

    Effect.loop state looper
    |> InternalTask.fromEffect

## Create a task that always succeeds with the value provided.
## 
## For example the following task always succeeds with the [Str](https://www.roc-lang.org/builtins/Str) `"Louis"`.
## ```
## getName : Task.Task Str []
## getName = Task.succeed "Louis"
## ```
##
succeed : ok -> Task ok *
succeed = \ok -> InternalTask.succeed ok

## Create a task that always failes with the error provided.
## 
## For example the following task always fails with the tag `CustomError Str`.
## ```
## customError : Str -> Task.Task {} [CustomError Str]
## customError = \err -> Task.fail (CustomError err)
## ```
##
fail : err -> Task * err
fail = \err -> InternalTask.fail err

## Transform a given Task with a function that handles the success or error case 
## and returns another task based on that.
##
## This is useful for chaining tasks together or performing error handling and 
## recovery.
## 
## Consider a the following task;
##
## `canFail : Task {} [Failure, AnotherFail, YetAnotherFail]`
## 
## We can use [attempt] to handle the failure cases using the following;
## ```
## result <- canFail |> Task.attempt
## when result is
##     Ok Success -> Stdout.line "Success!"
##     Err Failure -> Stdout.line "Oops, failed!"
##     Err AnotherFail -> Stdout.line "Ooooops, another failure!"
##     Err YetAnotherFail -> Stdout.line "Really big oooooops, yet again!"
## ```
## Here we know that the `canFail` task may fail, and so we use
## `Task.attempt` to convert the task to a `Result` and then use pattern 
## matching to handle the success and possible failure cases.
##
attempt : Task a b, (Result a b -> Task c d) -> Task c d
attempt = \task, transform ->
    effect = Effect.after
        (InternalTask.toEffect task)
        \result ->
            when result is
                Ok ok -> transform (Ok ok) |> InternalTask.toEffect
                Err err -> transform (Err err) |> InternalTask.toEffect

    InternalTask.fromEffect effect

## Take the success value from a given [Task] and use that to generate a new [Task].
##
## For example we can use this to run tasks in sequence like follows;
## ```
## # Prints "Hello World!\n" to standard output.
## {} <- Stdout.write "Hello "|> Task.await
## {} <- Stdout.srite "World!\n"|> Task.await
## 
## Task.succeed {}
## ```
await : Task a err, (a -> Task b err) -> Task b err
await = \task, transform ->
    effect = Effect.after
        (InternalTask.toEffect task)
        \result ->
            when result is
                Ok a -> transform a |> InternalTask.toEffect
                Err err -> Task.fail err |> InternalTask.toEffect

    InternalTask.fromEffect effect

## Take the error value from a given [Task] and use that to generate a new [Task].
##
## For example the following code will print `"Something went wrong!"` to standard 
## error if the `canFail` task fails.
## ```
## canFail 
## |> Task.onFail \_ -> Stderr.line "Something went wrong!"
## ```
onFail : Task ok a, (a -> Task ok b) -> Task ok b
onFail = \task, transform ->
    effect = Effect.after
        (InternalTask.toEffect task)
        \result ->
            when result is
                Ok a -> Task.succeed a |> InternalTask.toEffect
                Err err -> transform err |> InternalTask.toEffect

    InternalTask.fromEffect effect

## Transform the success value of a given [Task] with a given function.
##
## ```
## # Succeeds with a value of "Bonjour Louis!"
## Task.succeed "Louis"
## |> Task.map (\name -> "Bonjour \(name)!")
## ```
map : Task a err, (a -> b) -> Task b err
map = \task, transform ->
    effect = Effect.after
        (InternalTask.toEffect task)
        \result ->
            when result is
                Ok ok -> Task.succeed (transform ok) |> InternalTask.toEffect
                Err err -> Task.fail err |> InternalTask.toEffect

    InternalTask.fromEffect effect

## Transform the error value of a given [Task] with a given function.
##
## For example if the `canFail` task fails with an error, we can map that error
## to `CustomError` tag as follows;
## ```
## canFail
## |> Task.mapFail \_ -> CustomError
## ```
mapFail : Task ok a, (a -> b) -> Task ok b
mapFail = \task, transform ->
    effect = Effect.after
        (InternalTask.toEffect task)
        \result ->
            when result is
                Ok ok -> Task.succeed ok |> InternalTask.toEffect
                Err err -> Task.fail (transform err) |> InternalTask.toEffect

    InternalTask.fromEffect effect

## Use a Result among other Tasks by converting it into a [Task].
fromResult : Result ok err -> Task ok err
fromResult = \result ->
    when result is
        Ok ok -> succeed ok
        Err err -> fail err

## Apply a task to another task applicatively. This can be used with 
## [succeed] to build a [Task] that returns a record. 
##
## For example the following task returns a record with two fields, `apples` and
## `oranges`, each of which is a list of strings. If it fails it returns an
## error `NoFruitAvailable` tag.
## ```
## getFruitBasket : Task { apples : List Str, oranges : List Str } [NoFruitAvailable]
## getFruitBasket = Task.succeed {
##     apples: <- getFruit Apples |> Task.batch,
##     oranges: <- getFruit Oranges |> Task.batch,
## }
## ```
batch : Task a err -> (Task (a -> b) err -> Task b err)
batch = \current -> \next ->
        f <- next |> await

        map current f
