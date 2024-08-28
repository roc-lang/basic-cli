module [Task, fromEffect, toEffect, ok, err]

import Effect exposing [Effect]

Task ok err := Effect (Result ok err)

ok : a -> Task a *
ok = \a -> @Task (Effect.always (Ok a))

err : a -> Task * a
err = \a -> @Task (Effect.always (Err a))

fromEffect : Effect (Result ok err) -> Task ok err
fromEffect = \effect -> @Task effect

toEffect : Task ok err -> Effect (Result ok err)
toEffect = \@Task effect -> effect
