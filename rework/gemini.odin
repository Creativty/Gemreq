package gemreq

import ssl "../openssl"

import "core:c"
import "core:fmt"
import "core:mem"
import "core:net"
import "core:strconv"
import "core:strings"
import "core:sys/posix"

GEMINI :: "gemini"
PROTOCOL :: GEMINI + "://"

Gemini_Error :: union #shared_nil {
	net.Network_Error,
	cstring,
}

Endpoint :: struct {
	host: string,
	path: [dynamic]string,
	port: int,
}

parse_endpoint :: proc(src: string) -> (ep: Endpoint){
	ep.port = 1965
	ep.path = make([dynamic]string)

	url := strings.trim_space(src)
	if strings.has_prefix(url, PROTOCOL) do url = url[len(PROTOCOL):]

	host : Maybe(string) = nil
	for i in 0..<len(url) {
		if url[i] == ':' || url[i] == '/' {
			host = strings.clone(url[:i])
			break
		}
	}
	if host == nil do host = strings.clone(url)
	ep.host = host.(string)

	url = url[len(ep.host):]
	if strings.has_prefix(url, ":") {
		port_length: int

		url = url[1:]
		ep.port, _ = strconv.parse_int(url, n = &port_length)

		url = url[port_length:]
	}

	if strings.has_prefix(url, "/") {
		views := strings.split(url, "/")
		defer delete(views)

		for view in views {
			if len(view) == 0 do continue
			append(&ep.path, strings.clone(view))
		}
	}

	return ep
}

delete_endpoint :: proc(ep: Endpoint) {
	for level in ep.path do delete(level)
	delete(ep.path)
	delete(ep.host)
}

_gemini_request_ssl_init :: proc(sock: net.Socket) -> (ctx: ssl.SSL_CTX, inst: ssl.SSL, err: cstring) {
	// SSL context
	ctx = ssl.SSL_CTX_new(ssl.TLS_client_method())
	if ctx == nil do return nil, nil, posix.strerror(posix.errno())

	// SSL instance
	inst = ssl.SSL_new(ctx)
	if inst == nil {
		ssl.SSL_CTX_free(ctx)
		return nil, nil, posix.strerror(posix.errno())
	}

	// SSL shutdown
	ssl.SSL_set_shutdown(inst, ssl.SSL_Shutdown_Default)

	// SSL connection
	ssl.SSL_set_fd(inst, c.int(sock))

	return ctx, inst, nil
}

_gemini_request_ssl_destroy :: proc(ctx: ssl.SSL_CTX, inst: ssl.SSL) {
	ssl.SSL_free(inst)
	ssl.SSL_CTX_free(ctx)
}

_gemini_request_write :: proc(ep: Endpoint, request: ^strings.Builder) {
	strings.write_string(request, PROTOCOL)
	strings.write_string(request, ep.host)
	strings.write_string(request, ":")
	strings.write_int(request, ep.port)
	strings.write_string(request, "/")
	for level in ep.path {
		strings.write_string(request, level)
		if !strings.has_suffix(level, ".gmi") do strings.write_string(request, "/")
	}
	strings.write_string(request, "\r\n")

	strings.write_string(request, "\r\n")
}

gemini_request :: proc(ep: Endpoint) -> (response: string, err: Gemini_Error) {
	// Open backing socket
	sock := net.dial_tcp(ep.host, ep.port) or_return
	defer net.close(sock)

	// Open secure socket
	ssl_ctx, ssl_inst := _gemini_request_ssl_init(net.Socket(sock)) or_return
	defer _gemini_request_ssl_destroy(ssl_ctx, ssl_inst)

	// Attempt connection
	if ssl.SSL_connect(ssl_inst) < 0 {
		return response, posix.strerror(posix.errno())
	}
	defer ssl.SSL_shutdown(ssl_inst)

	request_b: strings.Builder
	strings.builder_init(&request_b)
	defer strings.builder_destroy(&request_b)

	_gemini_request_write(ep, &request_b)
	request := strings.to_string(request_b)

	if ssl.SSL_write(ssl_inst, raw_data(request), i32(len(request))) <= 0 {
		return response, posix.strerror(posix.errno())
	}

	BUFF_SIZE :: mem.Kilobyte * 1
	buff_temp : [BUFF_SIZE]u8
	buff_b	  : strings.Builder

	strings.builder_init(&buff_b)
	defer strings.builder_destroy(&buff_b)
	for {
		n := ssl.SSL_read(ssl_inst, raw_data(buff_temp[:]), BUFF_SIZE)
		if n <= 0 do break

		strings.write_string(&buff_b, transmute(string)buff_temp[:n])
	}

	resp_tmp := strings.to_string(buff_b)
	response  = strings.clone(resp_tmp)
	return response, nil
}

Document :: struct {
	body: []u8,
	status: int,
	location: Maybe(string),
	media_type: Maybe(string),
}

gemini_parse :: proc(src: string) -> (document: Document) {
	r := reader_make(src)

	status := reader_read_int(&r)
	reader_skip_whitespace(&r)
	rest := reader_read_delimiter(&r, "\r\n")

	fmt.println(status, rest)
	return
}
