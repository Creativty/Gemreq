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
_request_write :: proc(ep: Endpoint, request: ^strings.Builder) {
	strings.write_string(request, "gemini://")
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

resolve_endpoint :: proc(browser: ^Browser, location: uri.URI) -> (endpoint: Endpoint, ok: bool) {
	assert(location.opaque == "")
	assert(location.scheme == "" || location.scheme == "gemini")
	sync.mutex_lock(&browser.endpoint_mutex)
	defer sync.mutex_unlock(&browser.endpoint_mutex)

	endpoint.path = make([dynamic]string)
	if ep_ctx, ctx_exists := browser.endpoint.(Endpoint); ctx_exists && location.host == "" {
		endpoint.port = ep_ctx.port
		endpoint.host = strings.clone(ep_ctx.host)

		if !strings.has_prefix(location.path, "/") {
			path_capacity	:= len(ep_ctx.path)
			if len(ep_ctx.path) > 0 && strings.has_suffix(slice.last(ep_ctx.path[:]), ".gmi") do path_capacity -= 1
			path_ctx		:= strings.join(ep_ctx.path[:path_capacity], "/")
			path_rel		:= strings.join({ path_ctx, location.path }, "/")
			path			:= slashpath.clean(path_rel)
			components		:= strings.split(path, "/")
			defer {
				delete(components)
				delete(path_ctx)
				delete(path_rel)
				delete(path)
			}

			for component in components {
				if len(component) == 0 do continue
				append(&endpoint.path, strings.clone(component))
			}
		} else {
			path		:= slashpath.clean(location.path)
			components	:= strings.split(path, "/")
			defer {
				delete(components)
				delete(path)
			}

			for component in components {
				if len(component) == 0 do continue
				append(&endpoint.path, strings.clone(component))
			}
		}
	} else {
		log.assertf(location.host != "", "location %#v", location)
		endpoint.port = GEMINI_PORT
		endpoint.host = strings.clone(location.host)
		if len(location.port) > 0 do endpoint.port = strconv.parse_int(location.port) or_return
		path := slashpath.clean(location.path)
		components := strings.split(path, "/")
		defer {
			delete(path)
			delete(components)
		}
		for component in components {
			if len(component) == 0 do continue
			append(&endpoint.path, strings.clone(component))
		}
	}
	return endpoint, true
}

delete_endpoint :: proc(ep: Endpoint) {
	for level in ep.path do delete(level)
	delete(ep.path)
	delete(ep.host)
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
