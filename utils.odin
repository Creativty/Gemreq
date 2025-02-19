package gemini

import "core:sys/posix"

HOSTNAME	:: "envs.net"
PORT		:: 1965

errno :: proc() -> cstring {
	return posix.strerror(posix.errno())
}
