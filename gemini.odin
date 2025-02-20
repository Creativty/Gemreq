package gemini

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

GEMINI_PORT :: 1965
GEMINI_PROTOCOL :: "gemini://"

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

Gemini_Document :: struct {
	mime: Maybe(string),
	location: Maybe(string),
	status: Gemini_Status,
	elements: [dynamic]Gemini_Element,
}

gemini_delete :: proc(doc: ^Gemini_Document) {
	if doc.mime != nil do delete(doc.mime.(string))
	if doc.location != nil do delete(doc.location.(string))
	clear(&doc.elements)
	delete(doc.elements)
}

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

reader_read_delimiter :: proc(br: ^bufio.Reader, delimiter: string, allocator := context.allocator) -> (text: string, err: Gemini_Error) {
	sb: strings.Builder
	strings.builder_init(&sb, allocator)

	chars := make([dynamic]u8, allocator = allocator)
	defer delete(chars)

	for {
		peek := bufio.reader_peek(br, len(delimiter)) or_return
		if strings.has_prefix(string(peek), delimiter) {
			for i in 0..<len(delimiter) do bufio.reader_read_byte(br) or_return
			break
		}
		char := bufio.reader_read_byte(br) or_return
		append(&chars, char)
	}
	text = strings.clone(string(chars[:]), allocator = allocator) or_return
	return
}

gemini_parse_header :: proc(doc: ^Gemini_Document, br: ^bufio.Reader, allocator := context.allocator) -> (err: Gemini_Error) {
	// Read status number
	status_text := reader_read_delimiter(br, " ", allocator) or_return
	status_number, _ := strconv.parse_int(status_text)
	doc.status = Gemini_Status(status_number)

	// Read extra data (sometimes status associated)
	#partial switch doc.status {
	case .Success:
		doc.mime = reader_read_delimiter(br, "\r\n", allocator) or_return
	case .Redirect_Temporary, .Redirect_Permanent:
		doc.location = reader_read_delimiter(br, "\r\n", allocator) or_return
	// TODO(xenobas): Handle other status codes
	}
	return
}

gemini_parse :: proc(src: string, allocator := context.allocator) -> (doc: Gemini_Document, err: Gemini_Error) {
	doc.mime = nil
	doc.elements = make([dynamic]Gemini_Element, allocator = allocator)

	sr: strings.Reader
	ir := strings.to_reader(&sr, src)

	br: bufio.Reader
	bufio.reader_init(&br, ir, allocator = allocator)
	defer bufio.reader_destroy(&br)

	gemini_parse_header(&doc, &br, allocator) or_return
	for {
		text_untrimmed, err := reader_read_delimiter(&br, "\n", allocator)
		if err == .EOF do break
		if err != nil do return

		text := strings.trim(text_untrimmed, "\n ")
		if len(text) == 0 do continue

		text_parse: switch {
		case strings.has_prefix(text, "=> "):
			if end := strings.index_any(text[3:], " \t"); end != -1 {
				text = text[3:]
				link: Gemini_Element_Link
				link.url = strings.trim(strings.clone(text[:end], allocator), "\t\n ")
				link.text = strings.trim(strings.clone(text[end:], allocator), "\t\n ")
				delete(text_untrimmed)
				append(&doc.elements, link)
				break text_parse
			}
		fallthrough
		case:
			heading := 0
			for rune in text {
				if rune == '#' do heading += 1
				else do break
			}
			if text[heading] != ' ' do heading = 0
			append(&doc.elements, Gemini_Element_Text{
				strings.trim(text[heading:], "\t\n "),
				heading,
			})
		}
	}
	return
}

gemini_parse_url :: proc(url: string, allocator := context.allocator) -> (hostname: string, port: int, path: string, ok: bool) {
	hostname_start, hostname_length: int
	if strings.has_prefix(url, GEMINI_PROTOCOL) do hostname_start = len(GEMINI_PROTOCOL)

	// Hostname
	for hostname_length < len(url[hostname_start:]) {
		portion := url[hostname_start:]
		if portion[hostname_length] == ':' || portion[hostname_length] == '/' do break
		hostname_length += 1
	}
	// Port (Optional)
	port_length: int
	port_start := hostname_start + hostname_length - 1
	if url[port_start] == ':' {
		port_start += 1
		for port_length < len(url[port_start:]) {
			portion := url[hostname_start:]
			if portion[port_length] < '0' || portion[port_length] <= '9' do break
			port_length += 1
		}
	}
	// Path (Optional)
	path_length: int
	path_start := port_start + port_length
	if url[path_start] == '/' do path_length = len(url[path_start:])

	port = GEMINI_PORT
	if port_length == 0 {
		port_parsed, port_ok := strconv.parse_int(url[port_start:][:port_length])
		if port_ok do port = port_parsed
	}
	path = strings.clone("/" if path_length == 0 else url[path_start:])
	hostname = strings.clone("" if hostname_length == 0 else url[hostname_start:][:hostname_length])
	return hostname, port, path, hostname_length > 0
}

gemini_status_is_redirect :: proc(status: Gemini_Status) -> (is_redirect: bool) {
	#partial switch status {
	case .Redirect_Temporary, .Redirect_Permanent:
		return true
	}
	return false
}
