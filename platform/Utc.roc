interface Utc
    exposes [
        Utc,
        now,
        toMillisSinceEpoch,
        fromMillisSinceEpoch,
        toNanosSinceEpoch,
        fromNanosSinceEpoch,
        deltaAsMillis,
        deltaAsNanos,
    ]
    imports [Effect, InternalTask, Task.{ Task }]

## Stores a timestamp as nanoseconds since UNIX EPOCH
Utc := I128 implements [Inspect]

## Duration since UNIX EPOCH
now : Task Utc *
now =
    Effect.posixTime
    |> Effect.map Num.toI128
    |> Effect.map @Utc
    |> Effect.map Ok
    |> InternalTask.fromEffect

# Constant number of nanoseconds in a millisecond
nanosPerMilli = 1_000_000

## Convert Utc timestamp to milliseconds
toMillisSinceEpoch : Utc -> I128
toMillisSinceEpoch = \@Utc nanos ->
    nanos // nanosPerMilli

## Convert milliseconds to Utc timestamp
fromMillisSinceEpoch : I128 -> Utc
fromMillisSinceEpoch = \millis ->
    @Utc (millis * nanosPerMilli)

## Convert Utc timestamp to nanoseconds
toNanosSinceEpoch : Utc -> I128
toNanosSinceEpoch = \@Utc nanos ->
    nanos

## Convert nanoseconds to Utc timestamp
fromNanosSinceEpoch : I128 -> Utc
fromNanosSinceEpoch = @Utc

## Calculate milliseconds between two Utc timestamps
deltaAsMillis : Utc, Utc -> U128
deltaAsMillis = \@Utc first, @Utc second ->
    firstCast = Num.bitwiseXor (Num.toU128 first) (Num.shiftLeftBy 1 127)
    secondCast = Num.bitwiseXor (Num.toU128 second) (Num.shiftLeftBy 1 127)
    (Num.absDiff firstCast secondCast) // nanosPerMilli

## Calculate nanoseconds between two Utc timestamps
deltaAsNanos : Utc, Utc -> U128
deltaAsNanos = \@Utc first, @Utc second ->
    firstCast = Num.bitwiseXor (Num.toU128 first) (Num.shiftLeftBy 1 127)
    secondCast = Num.bitwiseXor (Num.toU128 second) (Num.shiftLeftBy 1 127)
    Num.absDiff firstCast secondCast

