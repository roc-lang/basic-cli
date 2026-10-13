## Declare the native resource handles shared by the hosted effects.
##
## Every handle is the same opaque box holding a host-owned `U64`; the phantom
## `kind` makes each alias a distinct type, so passing the wrong kind of handle
## is a type error. The host allocates each kind in its own address range (see
## `src/resources.rs`), which is how it finds the destructor to run when the
## last reference is released.
##
## To add a kind, add one alias line here and register the Rust type under the
## same name in the `resource_kinds!` list in `src/resources.rs`.
Resource :: [].{
	Handle(kind) :: Box(U64)

	Child : Handle([ChildKind])
	FileReader : Handle([FileReaderKind])
	FileWriter : Handle([FileWriterKind])
	HttpResponse : Handle([HttpResponseKind])
	SqliteStmt : Handle([SqliteStmtKind])
	TcpConnection : Handle([TcpConnectionKind])
	TcpListener : Handle([TcpListenerKind])
}
