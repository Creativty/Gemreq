package ssl

import "core:c"
foreign import openssl "bin/libssl.so"

SSL :: distinct rawptr
SSL_CTX :: distinct rawptr
SSL_METHOD :: distinct rawptr

SSL_Shutdown_Mode :: enum c.int {
	SENT_SHUTDOWN = 1,
	RECEIVED_SHUTDOWN = 2,
}

SSL_Shutdown_Default :: bit_set[SSL_Shutdown_Mode]{ .SENT_SHUTDOWN, .RECEIVED_SHUTDOWN }

foreign openssl {
	TLS_client_method	:: proc() -> SSL_METHOD ---

	SSL_CTX_new			:: proc(method: SSL_METHOD) -> SSL_CTX ---
	SSL_CTX_free		:: proc(ctx: SSL_CTX) ---

	SSL_new				:: proc(ctx: SSL_CTX) -> SSL ---
	SSL_free			:: proc(ssl: SSL) ---
	SSL_read			:: proc(ssl: SSL, buf: [^]u8, num: c.int) -> int ---
	SSL_write			:: proc(ssl: SSL, buf: [^]u8, num: c.int) -> int ---
	SSL_set_fd			:: proc(ssl: SSL, socket: c.int) -> c.int ---
	SSL_connect			:: proc(ssl: SSL) -> c.int ---
	SSL_shutdown		:: proc(ssl: SSL) -> c.int ---
	SSL_set_shutdown	:: proc(ssl: SSL, mode: bit_set[SSL_Shutdown_Mode]) ---
}
