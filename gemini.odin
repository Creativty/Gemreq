package gemreq

import "uri"
import ssl "openssl"

import "core:c"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:net"
import "core:time"
import "core:sync"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sys/posix"
import "core:path/slashpath"

GEMINI_PORT	:: 1965

Endpoint :: struct {
	host: string,
	path: [dynamic]string, // TODO(XENOBAS): use string instead of [dynamic]string
	port: int,
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

Gemini_Error :: union #shared_nil {
	net.Network_Error,
	cstring,
}

@(private="file")
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

@(private="file")
_request_ssl_destroy :: proc(ctx: ssl.SSL_CTX, inst: ssl.SSL) {
	ssl.SSL_free(inst)
	ssl.SSL_CTX_free(ctx)
}

@(private="file")
_request_write :: proc(request: ^strings.Builder, ep: Endpoint) {
	strings.write_string(request, "gemini://")
	strings.write_string(request, ep.host)
	if len(ep.path) > 0 {
		path := strings.join(ep.path[:], "/")
		strings.write_string(request, path)
		if !strings.has_suffix(path, ".gmi") do strings.write_string(request, "/")
		delete(path)
	}
	strings.write_string(request, "\r\n\r\n")
}

@(private="file")
_request_write_uri :: proc(request: ^strings.Builder, location: uri.URI) {
	strings.write_string(request, "gemini://")
	if len(location.userinfo) > 0 {
		strings.write_string(request, location.userinfo)
		strings.write_rune(request, '@')
	}
	strings.write_string(request, location.host)
	if len(location.port) > 0 {
		strings.write_rune(request, ':')
		strings.write_string(request, location.port)
	}
	strings.write_string(request, location.path)
	if len(location.query) > 0 {
		strings.write_rune(request, '?')
		strings.write_string(request, location.query)
	}
	if len(location.fragment) > 0 {
		strings.write_rune(request, '#')
		strings.write_string(request, location.fragment)
	}
	log.debugf("written request with uri `%v`", strings.to_string(request^))
	strings.write_string(request, "\r\n\r\n")
}

resolve_uri :: proc(browser: ^Browser, reference: uri.URI) -> (location: uri.URI, ok: bool) {
	if base, exists := location_history(&browser.history); exists && reference.host == "" {
		return uri.resolve_reference(base.location, reference), true
	} else {
		return uri.clone(reference), true
	}
}

delete_endpoint :: proc(ep: Endpoint) {
	for level in ep.path do delete(level)
	delete(ep.path)
	delete(ep.host)
}

request_document_uri :: proc(location: uri.URI) -> (response: string, err: Gemini_Error) {
	// Timing start
	timing: time.Stopwatch
	time.stopwatch_start(&timing)

	log.debugf("sending request to %v", location)

	// Port
	port := GEMINI_PORT
	if len(location.port) > 0 do port, _ = strconv.parse_int(location.port)

	// Open backing socket
	sock := net.dial_tcp(location.host, port) or_return
	defer net.close(sock)
	log.debugf("connection established")

	// Open secure socket
	ssl_ctx, ssl_inst := _request_ssl_init(net.Socket(sock)) or_return
	defer _request_ssl_destroy(ssl_ctx, ssl_inst)

	// Attempt connection
	if ssl.SSL_connect(ssl_inst) < 0 {
		error := posix.strerror(posix.errno())
		log.errorf("could not secure connection reason %s", error)
		return response, error
	}
	defer ssl.SSL_shutdown(ssl_inst)

	log.debugf("connection is now secured")

	request_b: strings.Builder
	strings.builder_init(&request_b)
	defer strings.builder_destroy(&request_b)

	_request_write_uri(&request_b, location)
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

request_document :: proc(ep: Endpoint) -> (response: string, err: Gemini_Error) {
	// Timing start
	timing: time.Stopwatch
	time.stopwatch_start(&timing)

	log.debugf("endpoint %v", ep)

	// Open backing socket
	sock := net.dial_tcp(ep.host, ep.port) or_return
	defer net.close(sock)
	log.debugf("connection established")

	// Open secure socket
	ssl_ctx, ssl_inst := _request_ssl_init(net.Socket(sock)) or_return
	defer _request_ssl_destroy(ssl_ctx, ssl_inst)

	// Attempt connection
	if ssl.SSL_connect(ssl_inst) < 0 {
		error := posix.strerror(posix.errno())
		log.errorf("could not secure connection reason %s", error)
		return response, error
	}
	defer ssl.SSL_shutdown(ssl_inst)

	log.debugf("connection is now secured")

	request_b: strings.Builder
	strings.builder_init(&request_b)
	defer strings.builder_destroy(&request_b)

	_request_write(&request_b, ep)
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
	switch document.status {
	case 31, 30:
		reader_skip_whitespace(&r)
		text := reader_read_delimiter(&r, "\r\n")
		clear_document_layout(&document)
		navigate_enqueue(browser, text)
	case 20:
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
	case:
		log.panicf("unimplemented status code %d", document.status)
	}
	return
}

delete_document :: proc(document: Document) {
	delete(document.source)
	delete(document.elements)
}
