package gemreq

import "core:strings"
import "core:strconv"

Reader :: struct {
	length: int,
	index_last: int,
	index_curr: int,
	row, column: int,
	buffer: string,
}

reader_make :: proc(buffer: string) -> (r: Reader) {
	r.row = 1
	r.column = 1
	r.buffer = buffer
	r.length = len(buffer)
	return
}

reader_eof :: proc(r: ^Reader) -> bool {
	return reader_peek(r) == rune(0)
}

reader_peek :: proc(r: ^Reader) -> rune {
	if r.index_curr >= r.length || r.index_curr < 0 do return rune(0)
	return rune(r.buffer[r.index_curr])
}

reader_next :: proc(r: ^Reader) -> rune {
	char := reader_peek(r)
	if char != rune(0) {
		if char == '\n' {
			r.row     = 1
			r.column += 1
		}
		r.index_curr += 1
	}
	return char
}

reader_next_if :: proc(r: ^Reader, cond: proc(c: rune) -> bool) -> rune {
	if char := reader_peek(r); cond(char) do return reader_next(r)
	return rune(0)
}

reader_next_while :: proc(r: ^Reader, cond: proc (i: int, c: rune) -> bool) -> (n: int) {
	if cond == nil do return
	for !reader_eof(r) && cond(n, reader_peek(r)) {
		reader_next(r)
		n += 1
	}
	return n
}

reader_skip_while :: proc(r: ^Reader, cond: proc(i: int, c: rune) -> bool) -> (n: int) {
	n = reader_next_while(r, cond)
	r.index_last = r.index_curr
	return n
}

reader_skip_whitespace :: proc(r: ^Reader) -> (n: int) {
	is_whitespace :: proc(_: int, c: rune) -> bool {
		return c == ' ' || c == '\t' || c == '\f' || c == '\n' || c == '\r' || c == '\v'
	}
	return reader_skip_while(r, is_whitespace)
}

reader_consume :: proc(r: ^Reader) -> (token: string) {
	token = r.buffer[r.index_last:][:r.index_curr - r.index_last]
	r.index_last = r.index_curr
	return token
}

reader_read_int :: proc(r: ^Reader) -> (n: int) {
	r.index_last = r.index_curr

	is_digit :: proc(_: int, c: rune) -> bool {
		return c >= '0' && c <= '9'
	}
	reader_next_while(r, is_digit)
	token := reader_consume(r)

	n, _ = strconv.parse_int(token)
	return n
}

reader_read_delimiter :: proc(r: ^Reader, delimiter: string) -> (token: string) {

	r.index_last = r.index_curr
	for !reader_eof(r) {
		if strings.has_prefix(r.buffer[r.index_curr:], delimiter) do break
		reader_next(r)
	}
	token = reader_consume(r)

	if strings.has_prefix(r.buffer[r.index_curr:], delimiter) {
		for i in 0..<len(delimiter) do reader_next(r)
	}
	return token
}
