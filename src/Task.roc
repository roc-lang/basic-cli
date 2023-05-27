interface Task
    exposes [
        Task,
        fromInner,
        succeed,
        fail,
        await,
        # map,
        # mapFail,
        # onFail,
        # attempt,
        # forever,
        # loop,
        # fromResult,
    ]
    imports [Op.{ Op }]

Task ok err := (Result ok err -> Op) -> Op

fromInner = @Task

succeed : ok -> Task ok *
succeed = \ok -> @Task \toNext -> toNext (Ok ok)

fail : err -> Task * err
fail = \err-> @Task \toNext -> toNext (Err err)

await : Task ok1 err, (ok1 -> Task ok2 err) -> Task ok2 err
await = \@Task fromResult, next ->
    continue <- fromInner
    result <- fromResult
    @Task inner =
        when result is
            Ok v -> next v
            Err e -> fail e

    inner continue
