module [
    DateTime,
    to_iso_8601,
    epoch_millis_to_datetime,
]

DateTime : { year : I128, month : I128, day : I128, hours : I128, minutes : I128, seconds : I128 }

to_iso_8601 : DateTime -> Str
to_iso_8601 = |{ year, month, day, hours, minutes, seconds }|
    year_str = year_with_padded_zeros(year)
    month_str = month_with_padded_zeros(month)
    day_str = day_with_padded_zeros(day)
    hour_str = hours_with_padded_zeros(hours)
    minute_str = minutes_with_padded_zeros(minutes)
    seconds_str = seconds_with_padded_zeros(seconds)

    "${year_str}-${month_str}-${day_str}T${hour_str}:${minute_str}:${seconds_str}Z"

year_with_padded_zeros : I128 -> Str
year_with_padded_zeros = |year|
    year_str = Num.to_str(year)
    if year < 10 then
        "000${year_str}"
    else if year < 100 then
        "00${year_str}"
    else if year < 1000 then
        "0${year_str}"
    else
        year_str

month_with_padded_zeros : I128 -> Str
month_with_padded_zeros = |month|
    month_str = Num.to_str(month)
    if month < 10 then
        "0${month_str}"
    else
        month_str

day_with_padded_zeros : I128 -> Str
day_with_padded_zeros = month_with_padded_zeros

hours_with_padded_zeros : I128 -> Str
hours_with_padded_zeros = month_with_padded_zeros

minutes_with_padded_zeros : I128 -> Str
minutes_with_padded_zeros = month_with_padded_zeros

seconds_with_padded_zeros : I128 -> Str
seconds_with_padded_zeros = month_with_padded_zeros

is_leap_year : I128 -> Bool
is_leap_year = |year|
    (year % 4 == 0)
    and # divided evenly by 4 unless...
    (
        (year % 100 != 0)
        or # divided by 100 not a leap year
        (year % 400 == 0) # expecpt when also divisible by 400
    )

expect is_leap_year(2000)
expect is_leap_year(2012)
expect !(is_leap_year(1900))
expect !(is_leap_year(2015))
expect List.map([2023, 1988, 1992, 1996], is_leap_year) == [Bool.false, Bool.true, Bool.true, Bool.true]
expect List.map([1700, 1800, 1900, 2100, 2200, 2300, 2500, 2600], is_leap_year) == [Bool.false, Bool.false, Bool.false, Bool.false, Bool.false, Bool.false, Bool.false, Bool.false]

days_in_month : I128, I128 -> I128
days_in_month = |year, month|
    if List.contains([1, 3, 5, 7, 8, 10, 12], month) then
        31
    else if List.contains([4, 6, 9, 11], month) then
        30
    else if month == 2 then
        (if is_leap_year(year) then 29 else 28)
    else
        0

expect days_in_month(2023, 1) == 31 # January
expect days_in_month(2023, 2) == 28 # February
expect days_in_month(1996, 2) == 29 # February in a leap year
expect days_in_month(2023, 3) == 31 # March
expect days_in_month(2023, 4) == 30 # April
expect days_in_month(2023, 5) == 31 # May
expect days_in_month(2023, 6) == 30 # June
expect days_in_month(2023, 7) == 31 # July
expect days_in_month(2023, 8) == 31 # August
expect days_in_month(2023, 9) == 30 # September
expect days_in_month(2023, 10) == 31 # October
expect days_in_month(2023, 11) == 30 # November
expect days_in_month(2023, 12) == 31 # December

epoch_millis_to_datetime : I128 -> DateTime
epoch_millis_to_datetime = |millis|
    seconds = millis // 1000
    minutes = seconds // 60
    hours = minutes // 60
    day = 1 + hours // 24
    month = 1
    year = 1970

    epoch_millis_to_datetime_help(
        {
            year,
            month,
            day,
            hours: hours % 24,
            minutes: minutes % 60,
            seconds: seconds % 60,
        },
    )

epoch_millis_to_datetime_help : DateTime -> DateTime
epoch_millis_to_datetime_help = |current|
    count_days_in_month = days_in_month(current.year, current.month)
    count_days_in_prev_month =
        if current.month == 1 then
            days_in_month((current.year - 1), 12)
        else
            days_in_month(current.year, (current.month - 1))

    if current.day < 1 then
        epoch_millis_to_datetime_help(
            { current &
                year: if current.month == 1 then current.year - 1 else current.year,
                month: if current.month == 1 then 12 else current.month - 1,
                day: current.day + count_days_in_prev_month,
            },
        )
    else if current.hours < 0 then
        epoch_millis_to_datetime_help(
            { current &
                day: current.day - 1,
                hours: current.hours + 24,
            },
        )
    else if current.minutes < 0 then
        epoch_millis_to_datetime_help(
            { current &
                hours: current.hours - 1,
                minutes: current.minutes + 60,
            },
        )
    else if current.seconds < 0 then
        epoch_millis_to_datetime_help(
            { current &
                minutes: current.minutes - 1,
                seconds: current.seconds + 60,
            },
        )
    else if current.day > count_days_in_month then
        epoch_millis_to_datetime_help(
            { current &
                year: if current.month == 12 then current.year + 1 else current.year,
                month: if current.month == 12 then 1 else current.month + 1,
                day: current.day - count_days_in_month,
            },
        )
    else
        current

# test 1000 ms before epoch
expect
    str = -1000 |> epoch_millis_to_datetime |> to_iso_8601
    str == "1969-12-31T23:59:59Z"

# test 1 hour, 1 minute, 1 second before epoch
expect
    str = (-3600 * 1000 - 60 * 1000 - 1000) |> epoch_millis_to_datetime |> to_iso_8601
    str == "1969-12-31T22:58:59Z"

# test 1 month before epoch
expect
    str = (-1 * 31 * 24 * 60 * 60 * 1000) |> epoch_millis_to_datetime |> to_iso_8601
    str == "1969-12-01T00:00:00Z"

# test 1 year before epoch
expect
    str = (-1 * 365 * 24 * 60 * 60 * 1000) |> epoch_millis_to_datetime |> to_iso_8601
    str == "1969-01-01T00:00:00Z"

# test 1st leap year before epoch
expect
    str = (-1 * (365 + 366) * 24 * 60 * 60 * 1000) |> epoch_millis_to_datetime |> to_iso_8601
    str == "1968-01-01T00:00:00Z"

# test last day of 1st year after epoch
expect
    str = (364 * 24 * 60 * 60 * 1000) |> epoch_millis_to_datetime |> to_iso_8601
    str == "1970-12-31T00:00:00Z"

# test last day of 1st month after epoch
expect
    str = (30 * 24 * 60 * 60 * 1000) |> epoch_millis_to_datetime |> to_iso_8601
    str == "1970-01-31T00:00:00Z"

# test 1_700_005_179_053 ms past epoch
expect
    str = 1_700_005_179_053 |> epoch_millis_to_datetime |> to_iso_8601
    str == "2023-11-14T23:39:39Z"

# test 1000 ms past epoch
expect
    str = 1_000 |> epoch_millis_to_datetime |> to_iso_8601
    str == "1970-01-01T00:00:01Z"

# test 1_000_000 ms past epoch
expect
    str = 1_000_000 |> epoch_millis_to_datetime |> to_iso_8601
    str == "1970-01-01T00:16:40Z"

# test 1_000_000_000 ms past epoch
expect
    str = 1_000_000_000 |> epoch_millis_to_datetime |> to_iso_8601
    str == "1970-01-12T13:46:40Z"

# test 1_600_005_179_000 ms past epoch
expect
    str = 1_600_005_179_000 |> epoch_millis_to_datetime |> to_iso_8601
    str == "2020-09-13T13:52:59Z"
