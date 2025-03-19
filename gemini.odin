package gemreq

import ssl "openssl"

import "core:c"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:net"
import "core:time"
import "core:sync"
import "core:strconv"
import "core:strings"
import "core:sys/posix"

GEMINI :: "gemini"
PROTOCOL :: GEMINI + "://"

Endpoint :: struct {
	host: string,
	path: [dynamic]string,
	port: int,
}

clone_endpoint :: proc(src: Endpoint) -> (clone: Endpoint) {
	clone.port = src.port
	clone.host = strings.clone(src.host)
	clone.path = make([dynamic]string)
	for entry in src.path {
		entry_clone := strings.clone(entry)
		append(&clone.path, entry_clone)
	}
	return
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
			view := strings.trim_left(view, "+")
			part := strings.clone(view)
			append(&ep.path, part)
		}
	}

	return ep
}

// TODO(XENOBAS): Implement URI encoding.
// TODO(XENOBAS): Add support for ../. relative path
resolve_endpoint :: proc(browser: ^Browser, url: string) -> (ep: Endpoint, is_external: bool) {
	url := url
	sync.mutex_guard(&browser.endpoint_mutex)
	ep_parent, ep_parent_exists := browser.endpoint.(Endpoint)
	if !ep_parent_exists || strings.contains(url, "://") {
		// Absolute URL
		if strings.has_prefix(url, "gemini://") do return parse_endpoint(url), false
		return ep, true
	} else if strings.has_prefix(url, "/") || strings.has_prefix(url, "~") {
		assert(ep_parent_exists, "invalid url expected a parent endpoint existing")

		// Absolute path
		url = strings.trim_left(url, "/~")

		ep = clone_endpoint(ep_parent)
		for entry in ep.path do delete(entry)
		clear(&ep.path)

		path := strings.split(url, "/")
		defer delete(path)

		for entry in path {
			if len(entry) == 0 do continue
			entry_clone := strings.clone(entry)
			append(&ep.path, entry_clone)
		}
		return ep, false
	} else {
		assert(ep_parent_exists, "invalid url expected a parent endpoint existing")

		// Relative path
		url = strings.trim_left(url, "+")
		ep = clone_endpoint(ep_parent)

		if len(ep.path) > 0 && strings.contains(ep.path[len(ep.path) - 1], ".") {
			pop(&ep.path)
		}

		path := strings.split(url, "/")
		defer delete(path)

		for entry in path {
			if len(entry) == 0 do continue
			entry_clone := strings.clone(entry)
			append(&ep.path, entry_clone)
		}
		return ep, false
	}
}

delete_endpoint :: proc(ep: Endpoint) {
	for level in ep.path do delete(level)
	delete(ep.path)
	delete(ep.host)
}

Gemini_Error :: union #shared_nil {
	net.Network_Error,
	cstring,
}

_request_ssl_init :: proc(sock: net.Socket) -> (ctx: ssl.SSL_CTX, inst: ssl.SSL, err: cstring) {
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

_request_ssl_destroy :: proc(ctx: ssl.SSL_CTX, inst: ssl.SSL) {
	ssl.SSL_free(inst)
	ssl.SSL_CTX_free(ctx)
}

_request_write :: proc(ep: Endpoint, request: ^strings.Builder) {
	strings.write_string(request, PROTOCOL)
	strings.write_string(request, ep.host)
	strings.write_string(request, "/")
	if len(ep.path) > 0 {
		path := strings.join(ep.path[:], "/")
		strings.write_string(request, path)
		if !strings.has_suffix(path, ".gmi") do strings.write_string(request, "/")
		delete(path)
	}
	strings.write_string(request, "\r\n")

	strings.write_string(request, "\r\n")
}

request_document :: proc(ep: Endpoint) -> (response: string, err: Gemini_Error) {
	// Timing start
	timing: time.Stopwatch
	time.stopwatch_start(&timing)

	log.debugf("request_document :: endpoint %v", ep)

	// Open backing socket
	sock := net.dial_tcp(ep.host, ep.port) or_return
	defer net.close(sock)
	log.debugf("request_document :: connection established")

	// Open secure socket
	ssl_ctx, ssl_inst := _request_ssl_init(net.Socket(sock)) or_return
	defer _request_ssl_destroy(ssl_ctx, ssl_inst)

	// Attempt connection
	if ssl.SSL_connect(ssl_inst) < 0 {
		error := posix.strerror(posix.errno())
		log.errorf("request_document :: could not secure connection reason %s", error)
		return response, error
	}
	defer ssl.SSL_shutdown(ssl_inst)

	log.debugf("request_document :: connection is now secured")

	request_b: strings.Builder
	strings.builder_init(&request_b)
	defer strings.builder_destroy(&request_b)

	_request_write(ep, &request_b)
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

	// Timing end
	time.stopwatch_stop(&timing)
	timing_duration := time.stopwatch_duration(timing)
	log.debugf("took %v.", timing_duration)

	resp_tmp := strings.to_string(buff_b)
	response  = strings.clone(resp_tmp)

	return response, nil
}

Element :: struct {
	size: [2]f32,
	offset: f32,
	gemtext: Gemtext,
	is_preformatted: bool,
}

Document :: struct {
	status: int,
	source: string,
	height: f32,
	elements: [dynamic]Element,
	gemtexts: [dynamic]Gemtext,
}

parse_document :: proc(browser: ^Browser, source: string, source_do_clone := false) -> (document: Document) {
	document.source = strings.clone(source) if source_do_clone else source
	document.gemtexts = make([dynamic]Gemtext)
	document.elements = make([dynamic]Element)

	timing: time.Stopwatch
	time.stopwatch_start(&timing)
	defer {
		time.stopwatch_stop(&timing)

		timing_duration := time.stopwatch_duration(timing)
		log.debugf("timing %v.", timing_duration)
	}

	r := reader_make(document.source)
	document.status = reader_read_int(&r)
	if document.status != 20 do log.panicf("todo: implement more status codes, received = %d", document.status)
	log.debugf("status %d", document.status)

	reader_skip_whitespace(&r)
	mime := reader_read_delimiter(&r, "\r\n")
	mime_parts := strings.split_multi(mime, { ";", " " })
	defer delete(mime_parts)
	if len(mime_parts) < 1 || mime_parts[0] != "text/gemini" do log.panicf("todo: implement more media types, received = %s", mime)
	log.debugf("mime %s", mime)

	in_preformat: bool
	clear_document_layout(&document)
	config_empty := gemtext_options(browser, .Empty)
	for !reader_eof(&r) {
		line := reader_read_delimiter(&r, "\n") // NOTE(XENOBAS): Gemtext uses \n for delimiters unlike Gemini data response
		gemtext := gemtext_parse(line, in_preformat)
		append(&document.gemtexts, gemtext)
	}
	update_document_layout(browser, &document)
	return
}

delete_document :: proc(document: Document) {
	delete(document.source)
	delete(document.elements)
}
