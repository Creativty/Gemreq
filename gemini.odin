package gemini

import "openssl"

import "core:c"
import "core:os"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:net"
import "core:sys/posix"

HOSTNAME	:: "envs.net"
PORT		:: 1965

gemini_connect :: proc() -> net.TCP_Socket {
	socket, err := net.dial_tcp(HOSTNAME, PORT)
	if err != nil {
		fmt.eprintfln("gemini: could not dial gemini:://%s:%d / %v", HOSTNAME, PORT, err)
		os.exit(1)
	}
	return socket
}

errno :: proc() -> cstring {
	return posix.strerror(posix.errno())
}

main :: proc() {
	socket := gemini_connect()
	defer net.close(socket)

	ssl_ctx := openssl.SSL_CTX_new(openssl.TLS_client_method())
	if ssl_ctx == nil {
		fmt.eprintfln("gemini: could not create an OpenSSL context / %v", errno())
		os.exit(1)
	}
	defer openssl.SSL_CTX_free(ssl_ctx)

	ssl := openssl.SSL_new(ssl_ctx)
	defer openssl.SSL_free(ssl)

	openssl.SSL_set_fd(ssl, c.int(socket))

	if openssl.SSL_connect(ssl) < 0 {
		fmt.eprintfln("gemini: could not establish an OpenSSL connection / %v", errno())
		os.exit(1)
	}

	REQUEST : string :	  "gemini://" + HOSTNAME + "\r\n" // \
						// + "\r\n"
						// + "Host: gemini://aindjare.com\r\n" \
	if openssl.SSL_write(ssl, raw_data(REQUEST), len(REQUEST)) <= 0 do fmt.eprintfln("gemini: could not write the request / TODO!")
	else {
		BUF_SIZE :: 1 * mem.Kilobyte
		buf: [BUF_SIZE]u8
		for {
			n := openssl.SSL_read(ssl, raw_data(buf[:]), BUF_SIZE)
			if n <= 0 do break
			text := transmute(string)buf[:]
			fmt.print(text)
		}
		fmt.println()
	}

	openssl.SSL_set_shutdown(ssl, openssl.SSL_Shutdown_Default)
	openssl.SSL_shutdown(ssl)
}
