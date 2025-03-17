package uri

import "core:strings"

// RFC3986		Uniform Resource Identifier (URI): Generic Syntax
// Reference:	  https://datatracker.ietf.org/doc/html/rfc3986

Authority :: struct {
	host: string,
	port: string,
}

URI :: struct {
	// path: []string,
	// query: map[string]string,
	// fragment: Maybe(string),
	scheme: string,
	authority: Maybe(Authority),
}

parse_scheme :: proc(reader: ^Reader) -> (scheme: string, ok: bool) {
	is_scheme :: proc(i: int, c: rune) -> bool {
		if i == 0 do return is_alpha(c)
		return is_scheme_suffix(c)
	}
	reader_next_while(reader, is_scheme)
	scheme = reader_consume(reader)
	if len(scheme) == 0 || reader_next_if_rune(reader, ':') == rune(0) do return "", false
	return strings.clone(scheme), true
}

parse_authority_host :: proc(reader: ^Reader) -> (host: string, ok: bool) {
	is_host_ipv6 :: proc(_: int, c: rune) -> bool {
		return is_hex(c) || c == ':'
	}
	is_host_ipv4_regname :: proc(_: int, c: rune) -> bool {
		return c != ':'
	}
	is_host := is_host_ipv4_regname
	if reader_next_if_rune(reader, '[') != rune(0) do is_host = is_host_ipv6
	reader_next_while(reader, is_host)
	if is_host == is_host_ipv6 {
		if reader_next_if_rune(reader, ']') == rune(0) do return reader_consume(reader), false
	}
	host = strings.clone(reader_consume(reader))
	return host, true
}

parse_authority :: proc(reader: ^Reader) -> (authority_optional: Maybe(Authority), ok: bool) {
	is_authority_prefix :: proc(i: int, c: rune) -> bool {
		if i >= 2 do return false
		return c == '/'
	}
	if slashes_len := reader_skip_while(reader, is_authority_prefix); slashes_len < 2 {
		reader.index_curr -= slashes_len
		return nil, true
	}

	is_authority :: proc(_: int, c: rune) -> bool {
		return c != '#' && c != '/'
	}
	reader_next_while(reader, is_authority)
	authority_text := reader_consume(reader)
	authority_reader := reader_make(authority_text)

	authority: Authority
	// TODO(XENOBAS): implement `userinfo`
	// Reference: https://datatracker.ietf.org/doc/html/rfc3986#section-3.2.1

	// Host
	authority.host = parse_authority_host(&authority_reader) or_return
	if reader_next_if_rune(&authority_reader, ':') != rune(0) {
		is_port :: proc(_: int, c: rune) -> bool {
			return is_digit(c)
		}
		reader_next_while(&authority_reader, is_port)
		authority.port = strings.clone(reader_consume(&authority_reader)[1:])
	} else do authority.port = strings.clone("")
	return authority, true
}

parse :: proc(source: string) -> (uri: URI, ok: bool) {
	reader := reader_make(source)

	uri.scheme = parse_scheme(&reader) or_return
	uri.authority = parse_authority(&reader) or_return
	return uri, true
}

destroy :: proc(uri: URI) {
	if authority, ok := uri.authority.(Authority); ok {
		delete(authority.host)
		delete(authority.port)
	}
	delete(uri.scheme)
}
