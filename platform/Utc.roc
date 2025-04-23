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
now! = |{}|
    @Utc(Num.to_i128(Host.posix_time!({})))

# Constant number of nanoseconds in a millisecond
nanos_per_milli = 1_000_000

## Convert Utc timestamp to milliseconds
to_millis_since_epoch : Utc -> I128
to_millis_since_epoch = |@Utc(nanos)|
    nanos // nanos_per_milli

## Convert milliseconds to Utc timestamp
from_millis_since_epoch : I128 -> Utc
from_millis_since_epoch = |millis|
    @Utc((millis * nanos_per_milli))

## Convert Utc timestamp to nanoseconds
to_nanos_since_epoch : Utc -> I128
to_nanos_since_epoch = |@Utc(nanos)|
    nanos

## Convert nanoseconds to Utc timestamp
from_nanos_since_epoch : I128 -> Utc
from_nanos_since_epoch = @Utc

## Calculate milliseconds between two Utc timestamps
delta_as_millis : Utc, Utc -> U128
delta_as_millis = |utc_a, utc_b|
    (delta_as_nanos(utc_a, utc_b)) // nanos_per_milli

## Calculate nanoseconds between two Utc timestamps
delta_as_nanos : Utc, Utc -> U128
delta_as_nanos = |@Utc(nanos_a), @Utc(nanos_b)|
    # bitwise_xor for best performance
    nanos_a_shifted = Num.bitwise_xor(Num.to_u128(nanos_a), Num.shift_left_by(1, 127))
    nanos_b_shifted = Num.bitwise_xor(Num.to_u128(nanos_b), Num.shift_left_by(1, 127))

    Num.abs_diff(nanos_a_shifted, nanos_b_shifted)

## Convert Utc timestamp to ISO 8601 string.
## For example: 2023-11-14T23:39:39Z
to_iso_8601 : Utc -> Str
to_iso_8601 = |@Utc(nanos)|
    nanos
    |> Num.div_trunc(nanos_per_milli)
    |> InternalDateTime.epoch_millis_to_datetime
    |> InternalDateTime.to_iso_8601

# TESTS
expect delta_as_nanos(from_nanos_since_epoch(0), from_nanos_since_epoch(0)) == 0
expect delta_as_nanos(from_nanos_since_epoch(1), from_nanos_since_epoch(2)) == 1
expect delta_as_nanos(from_nanos_since_epoch(-1), from_nanos_since_epoch(1)) == 2
expect delta_as_nanos(from_nanos_since_epoch(Num.min_i128), from_nanos_since_epoch(Num.max_i128)) == Num.max_u128

expect delta_as_millis(from_millis_since_epoch(0), from_millis_since_epoch(0)) == 0
expect delta_as_millis(from_nanos_since_epoch(1), from_nanos_since_epoch(2)) == 0
expect delta_as_millis(from_millis_since_epoch(1), from_millis_since_epoch(2)) == 1
expect delta_as_millis(from_millis_since_epoch(-1), from_millis_since_epoch(1)) == 2
expect delta_as_millis(from_nanos_since_epoch(Num.min_i128), from_nanos_since_epoch(Num.max_i128)) == Num.max_u128 // nanos_per_milli
