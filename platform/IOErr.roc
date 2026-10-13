## Represents an I/O error that can occur during platform operations.
##
## **NotFound** - An entity was not found, often a file.
##
## **PermissionDenied** - The operation lacked the necessary privileges to complete.
##
## **BrokenPipe** - The operation failed because a pipe was closed.
##
## **AlreadyExists** - An entity already exists, often a file.
##
## **AddrInUse** - A socket address could not be bound because it is already in use.
##
## **AddrNotAvailable** - The requested socket address does not exist or is not local.
##
## **ConnectionRefused** - The remote host refused the connection.
##
## **ConnectionReset** - The remote host reset the connection.
##
## **Interrupted** - This operation was interrupted. Interrupted operations can typically be retried.
##
## **IsADirectory** - A filesystem operation expected a non-directory path.
##
## **NotADirectory** - A filesystem operation expected a directory path.
##
## **Unsupported** - This operation is unsupported on this platform. This means that the operation can never succeed.
##
## **OutOfMemory** - An operation could not be completed, because it failed to allocate enough memory.
##
## **TimedOut** - The operation did not complete within its timeout.
##
## **Other** - A custom error that does not fall under any other I/O error kind.
IOErr := [
	AddrInUse,
	AddrNotAvailable,
	AlreadyExists,
	BrokenPipe,
	ConnectionRefused,
	ConnectionReset,
	Interrupted,
	IsADirectory,
	NotFound,
	NotADirectory,
	Other(Str),
	OutOfMemory,
	PermissionDenied,
	TimedOut,
	Unsupported,
].{

	## Compare two I/O errors, so results that contain one work with `==`.
	is_eq : _

	## Convert an I/O error to a concise human-readable message.
	to_str : IOErr -> Str
	to_str = |err|
		match err {
			AddrInUse => "address is already in use"
			AddrNotAvailable => "address is not available"
			AlreadyExists => "entity already exists"
			BrokenPipe => "pipe is closed"
			ConnectionRefused => "connection was refused"
			ConnectionReset => "connection was reset"
			Interrupted => "operation was interrupted"
			IsADirectory => "expected a non-directory path, but found a directory"
			NotFound => "entity was not found"
			NotADirectory => "expected a directory, but found a non-directory path"
			Other(message) => message
			OutOfMemory => "operation could not allocate enough memory"
			PermissionDenied => "permission denied"
			TimedOut => "operation timed out"
			Unsupported => "operation is unsupported"
		}
}

expect IOErr.to_str(NotFound) == "entity was not found"
expect IOErr.to_str(Other("device unavailable")) == "device unavailable"

expect {
	result : Try({}, [FileErr(IOErr)])
	result = Err(FileErr(NotFound))
	result == Err(FileErr(NotFound))
}
expect {
	result : Try({}, [TcpErr(IOErr)])
	result = Err(TcpErr(TimedOut))
	result != Err(TcpErr(ConnectionReset))
}
expect {
	left : IOErr
	left = Other("a")
	left != Other("b")
}
