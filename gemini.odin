package gemreq

import "openssl"

import "core:c"
import "core:io"
import "core:os"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:net"
import "core:bufio"
import "core:bytes"
import "core:strings"
import "core:strconv"

Gemini_Element :: union {
	Gemini_Element_Text,
	Gemini_Element_Link,
}

Gemini_Element_Text :: struct {
	text: string,
	heading: int,
}

Gemini_Element_Link :: struct {
	url: string,
	text: string,
}

Gemini_Error :: union #shared_nil {
	mem.Allocator_Error,
	net.Network_Error,
	io.Error,
	cstring,
}

Gemini_Status :: enum {
	Unreachable,
	Input_Expected = 10,
	Input_Sensitive = 11,
	Success = 20,
	Redirect_Temporary = 30,
	Redirect_Permanent = 31,
	Failure_Temporary = 40,
	Failure_Temporary_Server_Unavailable = 41,
	Failure_Temporary_CGI = 42,
	Failure_Temporary_Proxy = 43,
	Failure_Temporary_Slow_Down = 44,
	Failure_Permanent = 50,
	Failure_Permanent_Not_Found = 51,
	Failure_Permanent_Gone = 52,
	Failure_Permanent_Proxy_Request_Refused = 53,
	Failure_Permanent_Bad_Request = 59,
	Client_Certificate = 60,
	Client_Certificate_Not_Authorized = 61,
	Client_Certificate_Not_Valid = 62,
}

Gemini_Document :: struct {
	mime: Maybe(string),
	location: Maybe(string),
	status: Gemini_Status,
	elements: [dynamic]Gemini_Element,
}

GEMINI_PORT :: 1965
GEMINI_PROTOCOL :: "gemini://"

gemini_fetch :: proc(hostname: string, port := GEMINI_PORT, path := "/", allocator := context.allocator) -> (doc: string, err: Gemini_Error) {
	// Open network socket
	socket := net.dial_tcp(hostname, port) or_return
	defer net.close(socket)

	// SSL context
	ssl_ctx := openssl.SSL_CTX_new(openssl.TLS_client_method())
	if ssl_ctx == nil do return doc, errno()
	defer openssl.SSL_CTX_free(ssl_ctx)
	// SSL instance
	ssl := openssl.SSL_new(ssl_ctx)
	if ssl == nil do return doc, errno()
	defer openssl.SSL_free(ssl)
	// SSL shutdown
	openssl.SSL_set_shutdown(ssl, openssl.SSL_Shutdown_Default)
	defer openssl.SSL_shutdown(ssl)
	// SSL connection
	openssl.SSL_set_fd(ssl, c.int(socket))
	if openssl.SSL_connect(ssl) < 0 do return doc, errno()

	// Prepare request
	request_sb: strings.Builder
	if _, err := strings.builder_init(&request_sb, allocator); err != nil do return doc, err
	defer strings.builder_destroy(&request_sb)

	strings.write_string(&request_sb, "gemini://")
	strings.write_string(&request_sb, hostname)
	strings.write_string(&request_sb, ":")
	strings.write_int(&request_sb, port)
	strings.write_string(&request_sb, path)
	strings.write_string(&request_sb, "\r\n")
	strings.write_string(&request_sb, "\r\n")
	request_bytes := strings.to_string(request_sb)

	// Send request
	if openssl.SSL_write(ssl, raw_data(request_bytes), cast(i32)len(request_bytes)) <= 0 do return doc, "OpenSSL could not write the request bytes"

	// Receive response
	BUFF_SIZE :: mem.Kilobyte * 1
	buff_temp : [BUFF_SIZE]u8
	buff_sb   : strings.Builder

	strings.builder_init(&buff_sb, allocator)
	defer strings.builder_destroy(&buff_sb)
	for {
		n := openssl.SSL_read(ssl, raw_data(buff_temp[:]), BUFF_SIZE)
		if n <= 0 do break
		strings.write_string(&buff_sb, transmute(string)buff_temp[:n])
	}
	doc = strings.clone(strings.to_string(buff_sb))
	return doc, nil
}

gemini_delete :: proc(doc: ^Gemini_Document) {
	if doc.mime != nil do delete(doc.mime.(string))
	if doc.location != nil do delete(doc.location.(string))
	clear(&doc.elements)
	delete(doc.elements)
}
