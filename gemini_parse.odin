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

@(private)
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

gemini_status_match_redirect :: proc(status: Gemini_Status) -> (is_redirect: bool) {
	#partial switch status {
	case .Redirect_Temporary, .Redirect_Permanent:
		return true
	}
	return false
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
			heading: int
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
