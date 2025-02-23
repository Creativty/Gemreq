package gemreq

import "core:sys/posix"

errno :: proc() -> cstring {
	return posix.strerror(posix.errno())
}
