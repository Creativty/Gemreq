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

gemini_status_to_description :: proc(status: Gemini_Status) -> string {
	switch status {
	case .Unreachable: return "Application bug, this error state should be unreachable, please check the logs."
	case .Input_Expected: return "The basic input status code. A client MUST prompt a user for input, it should be URI-encoded per [STD66] and sent as a query to the same URI that generated this response."
	case .Input_Sensitive: return "As per status code 10, but for use with sensitive input such as passwords. Clients should present the prompt as per status code 10, but the user's input should not be echoed to the screen to prevent it being read by \"shoulder surfers\"."
	case .Success: return "The server has successfully parsed and understood the request, and will serve up content of the given MIME type. "
	case .Redirect_Temporary: return "The basic redirection code. The redirection is temporary and the client should continue to request the content with the original URI."
	case .Redirect_Permanent: return "The location of the content has moved permanently to a new location, and clients SHOULD use the new location to retrieve the given content from then on."
	case .Failure_Temporary: return "An unspecified condition exists on the server that is preventing the content from being served, but a client can try again to obtain the content."
	case .Failure_Temporary_Server_Unavailable: return "The server is unavailable due to overload or maintenance. (cf HTTP 503)"
	case .Failure_Temporary_CGI: return "A CGI process, or similar system for generating dynamic content, died unexpectedly or timed out."
	case .Failure_Temporary_Proxy: return "A proxy request failed because the server was unable to successfully complete a transaction with the remote host. (cf HTTP 502, 504)"
	case .Failure_Temporary_Slow_Down: return "The server is requesting the client to slow down requests, and SHOULD use an exponential back off, where subsequent delays between requests are doubled until this status no longer returned."
	case .Failure_Permanent: return "This is the general permanent failure code."
	case .Failure_Permanent_Not_Found: return "The requested resource could not be found (you can't find things at Area 51) and no further information is available. It may exist in the future, it may not. Who knows?"
	case .Failure_Permanent_Gone: return "The resource requested is no longer available and will not be available again. Search engines and similar tools should remove this resource from their indices. Content aggregators should stop requesting the resource and convey to their human users that the subscribed resource is gone. (cf HTTP 410)"
	case .Failure_Permanent_Proxy_Request_Refused: return "The request was for a resource at a domain not served by the server and the server does not accept proxy requests."
	case .Failure_Permanent_Bad_Request: return "The server was unable to parse the client's request, presumably due to a malformed request, or the request violated the constraints listed in the Request section."
	case .Client_Certificate: return "The content requires a client certificate."
	case .Client_Certificate_Not_Authorized: return "The supplied client certificate is not authorised for accessing the particular requested resource. The problem is not with the certificate itself, which may be authorised for other resources."
	case .Client_Certificate_Not_Valid: return "The supplied client certificate was not accepted because it is not valid. This indicates a problem with the certificate in and of itself, with no consideration of the particular requested resource. The most likely cause is that the certificate's validity start date is in the future or its expiry date has passed, but this code may also indicate an invalid signature, or a violation of a X509 standard requirements."
	case:
		return ""
	}
}

gemini_status_to_text :: proc(status: Gemini_Status) -> string {
	switch status {
	case .Unreachable: return "Unreachable"
	case .Input_Expected: return "Input expected"
	case .Input_Sensitive: return "Input sensitive"
	case .Success: return "Success"
	case .Redirect_Temporary: return "Redirect temporary"
	case .Redirect_Permanent: return "Redirect permanent"
	case .Failure_Temporary: return "Temporary failure"
	case .Failure_Temporary_Server_Unavailable: return "Server unavailable"
	case .Failure_Temporary_CGI: return "CGI failure"
	case .Failure_Temporary_Proxy: return "Proxy failure"
	case .Failure_Temporary_Slow_Down: return "Slow down"
	case .Failure_Permanent: return "Server error"
	case .Failure_Permanent_Not_Found: return "Not found"
	case .Failure_Permanent_Gone: return "Gone"
	case .Failure_Permanent_Proxy_Request_Refused: return "Proxy request refused"
	case .Failure_Permanent_Bad_Request: return "Bad request"
	case .Client_Certificate: return "Client certificate"
	case .Client_Certificate_Not_Authorized: return "Unauthorized certificate"
	case .Client_Certificate_Not_Valid: return "Invalid certificate"
	case:
		return ""
	}
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
