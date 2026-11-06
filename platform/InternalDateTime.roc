## Convert Unix timestamps into UTC calendar dates for public time formatting.
##
## Dates use the proleptic Gregorian calendar with astronomical year numbering,
## so the year before 0001 is 0000 and the one before that is -0001.
InternalDateTime :: [].{
	DateTime : {
		day : I128,
		hours : I128,
		minutes : I128,
		month : I128,
		seconds : I128,
		year : I128,
	}

	## Format a date and time as ISO 8601 with second precision.
	##
	## Years 0000 to 9999 use four digits. Years outside that range use the
	## expanded form with a mandatory sign: `-0001-12-31T23:59:59Z`,
	## `+10000-01-01T00:00:00Z`.
	to_iso_8601 : DateTime -> Str
	to_iso_8601 = |{ year, month, day, hours, minutes, seconds }| {
		year_str = year_with_padded_zeros(year)
		month_str = two_digits(month)
		day_str = two_digits(day)
		hour_str = two_digits(hours)
		minute_str = two_digits(minutes)
		seconds_str = two_digits(seconds)

		"${year_str}-${month_str}-${day_str}T${hour_str}:${minute_str}:${seconds_str}Z"
	}

	## Convert milliseconds since the Unix epoch, negative before 1970, to a
	## calendar date and time. A partial second is floored, so one millisecond
	## before the epoch is 1969-12-31T23:59:59.
	epoch_millis_to_datetime : I128 -> DateTime
	epoch_millis_to_datetime = |millis| {
		total_seconds = floor_div(millis, 1_000)
		days = floor_div(total_seconds, 86_400)
		second_of_day = total_seconds - days * 86_400
		{ year, month, day } = civil_from_days(days)

		{
			year,
			month,
			day,
			hours: second_of_day // 3_600,
			minutes: (second_of_day % 3_600) // 60,
			seconds: second_of_day % 60,
		}
	}

	## Divide rounding toward negative infinity. `divisor` must be positive.
	floor_div : I128, I128 -> I128
	floor_div = |dividend, divisor| {
		quotient = dividend // divisor

		if quotient * divisor > dividend {
			quotient - 1
		} else {
			quotient
		}
	}

	## Convert a count of days since 1970-01-01 to a calendar date.
	##
	## The Gregorian calendar repeats every 400 years (146097 days). Counting
	## years from 1 March puts the leap day last, so the day of the year maps to
	## a month by plain arithmetic.
	civil_from_days : I128 -> { year : I128, month : I128, day : I128 }
	civil_from_days = |days| {
		# Days since 0000-03-01.
		shifted = days + 719_468
		era = floor_div(shifted, 146_097)
		day_of_era = shifted - era * 146_097
		year_of_era = (day_of_era - day_of_era // 1_460 + day_of_era // 36_524 - day_of_era // 146_096) // 365
		day_of_year = day_of_era - (365 * year_of_era + year_of_era // 4 - year_of_era // 100)
		shifted_month = (5 * day_of_year + 2) // 153
		day = day_of_year - (153 * shifted_month + 2) // 5 + 1
		month = if (shifted_month < 10) shifted_month + 3 else shifted_month - 9
		march_year = year_of_era + era * 400
		year = if (month <= 2) march_year + 1 else march_year

		{ year, month, day }
	}

	year_with_padded_zeros : I128 -> Str
	year_with_padded_zeros = |year| {
		magnitude = if (year < 0) 0 - year else year
		digits = magnitude.to_str()
		padded =
			if magnitude < 10 {
				"000${digits}"
			} else if magnitude < 100 {
				"00${digits}"
			} else if magnitude < 1000 {
				"0${digits}"
			} else {
				digits
			}

		if year < 0 {
			"-${padded}"
		} else if year > 9999 {
			"+${padded}"
		} else {
			padded
		}
	}

	two_digits : I128 -> Str
	two_digits = |value| {
		value_str = value.to_str()

		if value < 10 {
			"0${value_str}"
		} else {
			value_str
		}
	}
}

iso : I128 -> Str
iso = |millis| InternalDateTime.to_iso_8601(InternalDateTime.epoch_millis_to_datetime(millis))

expect iso(0) == "1970-01-01T00:00:00Z"
expect iso(999) == "1970-01-01T00:00:00Z"
expect iso(1_000) == "1970-01-01T00:00:01Z"
expect iso(86_399_999) == "1970-01-01T23:59:59Z"
expect iso(86_400_000) == "1970-01-02T00:00:00Z"
expect iso(951_782_400_000) == "2000-02-29T00:00:00Z"
expect iso(951_868_800_000) == "2000-03-01T00:00:00Z"
expect iso(1_709_164_800_000) == "2024-02-29T00:00:00Z"
expect iso(1_735_689_599_000) == "2024-12-31T23:59:59Z"
expect iso(1_735_689_600_000) == "2025-01-01T00:00:00Z"
expect iso(1_791_883_800_000) == "2026-10-13T09:30:00Z"
expect iso(4_107_542_400_000) == "2100-03-01T00:00:00Z"
expect iso(253_402_300_799_000) == "9999-12-31T23:59:59Z"
expect iso(253_402_300_800_000) == "+10000-01-01T00:00:00Z"

# Before the epoch: a partial second floors toward the past.
expect iso(-1) == "1969-12-31T23:59:59Z"
expect iso(-1_000) == "1969-12-31T23:59:59Z"
expect iso(-1_001) == "1969-12-31T23:59:58Z"
expect iso(-86_400_000) == "1969-12-31T00:00:00Z"
expect iso(-86_400_001) == "1969-12-30T23:59:59Z"
expect iso(-2_208_988_800_000) == "1900-01-01T00:00:00Z"
expect iso(-2_203_891_200_000) == "1900-03-01T00:00:00Z"
expect iso(-11_644_473_600_000) == "1601-01-01T00:00:00Z"
expect iso(-62_135_596_800_000) == "0001-01-01T00:00:00Z"
expect iso(-62_135_596_801_000) == "0000-12-31T23:59:59Z"
expect iso(-62_162_121_600_000) == "0000-02-29T00:00:00Z"
expect iso(-62_167_219_200_000) == "0000-01-01T00:00:00Z"
expect iso(-62_167_219_201_000) == "-0001-12-31T23:59:59Z"

expect InternalDateTime.floor_div(7, 2) == 3
expect InternalDateTime.floor_div(-7, 2) == -4
expect InternalDateTime.floor_div(-8, 2) == -4
expect InternalDateTime.floor_div(0, 2) == 0

# The furthest instants an I128 of nanoseconds can hold still convert.
expect iso(I128.highest // 1_000_000) == "+5391559471918239498981-03-22T13:41:55Z"
expect iso(I128.lowest // 1_000_000) == "-5391559471918239495042-10-11T10:18:04Z"
