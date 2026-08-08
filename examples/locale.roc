## Parse, encode, and inspect the system's preferred locales.
app [main!] { pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.21.0/4rAQg8kUYZ3Vksr4qMQHpaFYNiHSn9GgS7gVxghd1XYV.tar.zst" }

import pf.OsStr
import pf.Stdout
import pf.Locale

main! : List(OsStr) => Try({}, _)
main! = |_args| {

	example_locale : Locale
	example_locale = "en-US"

	Stdout.line!("Locale JSON example: ${Json.to_str(example_locale)}")?

	locale_str = match Locale.get!() {
		Ok(locale) => locale.to_str()
		Err(NotAvailable) => "<not available>"
	}

	Stdout.line!("The most preferred locale for this system or application: ${locale_str}")?

	all_locales = Locale.all!()
	locales_str = Str.join_with(all_locales.map(|locale| locale.to_str()), ", ")

	Stdout.line!("All available locales for this system or application: [${locales_str}]")?

	Ok({})
}
