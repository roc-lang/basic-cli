## Discover the native target and obtain evidence for OS-specific operations.
##
## Discovery is effectful. Methods on a returned target or witness are pure:
## the same value always describes the same target, including in shared code.
## Witnesses have no public constructors or codecs. Keep a witness and pass it
## to helpers that need the corresponding operating-system facilities.
System :: [].{
	Linux :: { proof : U8 }.{

		## Evidence that Linux supports the Unix API family.
		unix : Linux -> Unix
		unix = |_| Unix.{ proof: 0 }
	}

	MacOS :: { proof : U8 }.{

		## Evidence that macOS supports the Unix API family.
		unix : MacOS -> Unix
		unix = |_| Unix.{ proof: 0 }
	}

	Windows :: { proof : U8 }
	Unix :: { proof : U8 }

	## The architecture of a supported native host.
	Architecture : [X64, Arm64]

	## The native host selected by the platform bundle, not environment data.
	Target :: {
		architecture : Architecture,
		operating_system : [Linux(Linux), MacOS(MacOS), Windows(Windows)],
	}.{
		arch : Target -> Architecture
		arch = |target| target.architecture

		os : Target -> [Linux(Linux), MacOS(MacOS), Windows(Windows)]
		os = |target| target.operating_system
	}

	## Obtain target information and opaque operating-system witnesses.
	## This is supplied directly by the native host; there is no pure factory.
	target! : () => Target
}
