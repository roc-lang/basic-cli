Host := {
	args : List(Str),
}.{
	## Returns the arguments that this program was started with.
	args! : Host => List(Str)
}
