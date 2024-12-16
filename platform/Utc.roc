module [
    Utc,
    now!,
    to_millis_since_epoch,
    from_millis_since_epoch,
    to_nanos_since_epoch,
    from_nanos_since_epoch,
    delta_as_millis,
    delta_as_nanos,
]

import Host

## Stores a timestamp as nanoseconds since UNIX EPOCH
Utc := I128 implements [Inspect]

## Duration since UNIX EPOCH
now! : {} => Utc
now! = \{} ->
    currentEpoch = Host.posix_time! {} |> Num.toI128

    @Utc currentEpoch

# Constant number of nanoseconds in a millisecond
nanosPerMilli = 1_000_000

## Convert Utc timestamp to milliseconds
to_millis_since_epoch : Utc -> I128
to_millis_since_epoch = \@Utc nanos ->
    nanos // nanosPerMilli

## Convert milliseconds to Utc timestamp
from_millis_since_epoch : I128 -> Utc
from_millis_since_epoch = \millis ->
    @Utc (millis * nanosPerMilli)

## Convert Utc timestamp to nanoseconds
to_nanos_since_epoch : Utc -> I128
to_nanos_since_epoch = \@Utc nanos ->
    nanos

## Convert nanoseconds to Utc timestamp
from_nanos_since_epoch : I128 -> Utc
from_nanos_since_epoch = @Utc

## Calculate milliseconds between two Utc timestamps
delta_as_millis : Utc, Utc -> U128
delta_as_millis = \utcA, utcB ->
    (delta_as_nanos utcA utcB) // nanosPerMilli

## Calculate nanoseconds between two Utc timestamps
delta_as_nanos : Utc, Utc -> U128
delta_as_nanos = \@Utc nanosA, @Utc nanosB ->
    # bitwiseXor for best performance
    nanos_a_shifted = Num.bitwiseXor (Num.toU128 nanosA) (Num.shiftLeftBy 1 127)
    nanos_b_shifted = Num.bitwiseXor (Num.toU128 nanosB) (Num.shiftLeftBy 1 127)

    Num.absDiff nanos_a_shifted nanos_b_shifted

# TESTS
expect delta_as_nanos (from_nanos_since_epoch 0) (from_nanos_since_epoch 0) == 0
expect delta_as_nanos (from_nanos_since_epoch 1) (from_nanos_since_epoch 2) == 1
expect delta_as_nanos (from_nanos_since_epoch -1) (from_nanos_since_epoch 1) == 2
expect delta_as_nanos (from_nanos_since_epoch Num.minI128) (from_nanos_since_epoch Num.maxI128) == Num.maxU128

expect delta_as_millis (from_millis_since_epoch 0) (from_millis_since_epoch 0) == 0
expect delta_as_millis (from_nanos_since_epoch 1) (from_nanos_since_epoch 2) == 0
expect delta_as_millis (from_millis_since_epoch 1) (from_millis_since_epoch 2) == 1
expect delta_as_millis (from_millis_since_epoch -1) (from_millis_since_epoch 1) == 2
expect delta_as_millis (from_nanos_since_epoch Num.minI128) (from_nanos_since_epoch Num.maxI128) == Num.maxU128 // nanosPerMilli
