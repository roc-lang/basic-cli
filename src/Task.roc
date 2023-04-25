interface Task
    exposes [Task, succeed, fail, await, map, mapFail, onFail, attempt, forever, loop, fromResult, fromOp]
    imports [Op.{ Op, mapOp }]

Task ok err := [Return (Result ok err), Lift (Op (Task ok err))]

fromOp : Op (Task ok err) -> Task ok err
fromOp = \op -> @Task (Lift op)

succeed : ok -> Task ok *
succeed = \ok -> @Task (Return (Ok ok))

fail : err -> Task * err
fail = \err -> @Task (Return (Err err))

await : Task a err, (a -> Task b err) -> Task b err
await = \@Task task, f ->
    when task is
        Return (Ok v) -> f v
        Return (Err e) -> @Task (Return (Err e))
        Lift op -> @Task (Lift (mapOp op \task1 -> await task1 f))

attempt : Task a b, (Result a b -> Task c d) -> Task c d
attempt = \@Task task, f ->
    when task is
        Return res -> f res
        Lift op -> @Task (Lift (mapOp op \task1 -> attempt task1 f))

onFail : Task ok a, (a -> Task ok b) -> Task ok b
onFail = \@Task task, f ->
    when task is
        Return (Ok v) -> @Task (Return (Ok v))
        Return (Err e) -> f e
        Lift op -> @Task (Lift (mapOp op \task1 -> onFail task1 f))

map : Task a err, (a -> b) -> Task b err
map = \@Task task, f ->
    when task is
        Return (Ok v) -> @Task (Return (Ok (f v)))
        Return (Err e) -> @Task (Return (Err e))
        Lift op -> @Task (Lift (mapOp op \task1 -> map task1 f))

mapFail : Task ok a, (a -> b) -> Task ok b
mapFail = \@Task task, f ->
    when task is
        Return (Ok v) -> @Task (Return (Ok v))
        Return (Err e) -> @Task (Return (Err (f e)))
        Lift op -> @Task (Lift (mapOp op \task1 -> mapFail task1 f))

## Use a Result among other Tasks by converting it into a Task.
fromResult : Result ok err -> Task ok err
fromResult = \result ->
    when result is
        Ok ok -> succeed ok
        Err err -> fail err

loop : state, (state -> Task [Step state, Done done] err) -> Task done err
loop = \state, step ->
    task = step state
    res <- Task.attempt task
    when res is
        Ok (Step newState) ->
            loop newState step

        Ok (Done result) ->
            Task.succeed result

        Err e ->
            Task.fail e

forever : Task val err -> Task * err
forever = \task ->
    looper = \{} ->
        res <- Task.attempt task
        when res is
            Ok _ -> Task.succeed (Step {})
            Err e -> Task.fail e

    loop {} looper
