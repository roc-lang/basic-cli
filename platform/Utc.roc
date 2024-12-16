module [
    Utc,
    now!,
    to_millis_since_epoch,
    from_millis_since_epoch,
    to_nanos_since_epoch,
    from_nanos_since_epoch,
    delta_as_millis,
    delta_as_nanos,
    to_iso_8601,
]

import Host
import InternalDateTime

## Stores a timestamp as nanoseconds since UNIX EPOCH
Utc := I128 implements [Inspect]

## Duration since UNIX EPOCH
now! : {} => Utc
now! = \{} ->
    @Utc (Num.toI128 (Host.posix_time! {}))

# Constant number of nanoseconds in a millisecond
nanos_per_milli = 1_000_000

## Convert Utc timestamp to milliseconds
to_millis_since_epoch : Utc -> I128
to_millis_since_epoch = \@Utc nanos ->
    nanos // nanos_per_milli

## Convert milliseconds to Utc timestamp
from_millis_since_epoch : I128 -> Utc
from_millis_since_epoch = \millis ->
    @Utc (millis * nanos_per_milli)

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
    (delta_as_nanos utcA utcB) // nanos_per_milli

## Calculate nanoseconds between two Utc timestamps
delta_as_nanos : Utc, Utc -> U128
delta_as_nanos = \@Utc nanosA, @Utc nanosB ->
    # bitwiseXor for best performance
    nanos_a_shifted = Num.bitwiseXor (Num.toU128 nanosA) (Num.shiftLeftBy 1 127)
    nanos_b_shifted = Num.bitwiseXor (Num.toU128 nanosB) (Num.shiftLeftBy 1 127)

    Num.absDiff nanos_a_shifted nanos_b_shifted

## Convert Utc timestamp to ISO 8601 string
## Example: 2023-11-14T23:39:39Z
to_iso_8601 : Utc -> Str
to_iso_8601 = \@Utc nanos ->
    nanos
    |> Num.divTrunc nanos_per_milli
    |> InternalDateTime.epoch_millis_to_datetime
    |> InternalDateTime.to_iso_8601

# TESTS
expect delta_as_nanos (from_nanos_since_epoch 0) (from_nanos_since_epoch 0) == 0
expect delta_as_nanos (from_nanos_since_epoch 1) (from_nanos_since_epoch 2) == 1
expect delta_as_nanos (from_nanos_since_epoch -1) (from_nanos_since_epoch 1) == 2
expect delta_as_nanos (from_nanos_since_epoch Num.minI128) (from_nanos_since_epoch Num.maxI128) == Num.maxU128

expect delta_as_millis (from_millis_since_epoch 0) (from_millis_since_epoch 0) == 0
expect delta_as_millis (from_nanos_since_epoch 1) (from_nanos_since_epoch 2) == 0
expect delta_as_millis (from_millis_since_epoch 1) (from_millis_since_epoch 2) == 1
expect delta_as_millis (from_millis_since_epoch -1) (from_millis_since_epoch 1) == 2
expect delta_as_millis (from_nanos_since_epoch Num.minI128) (from_nanos_since_epoch Num.maxI128) == Num.maxU128 // nanos_per_milli
