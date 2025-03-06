package gemreq

import "core:strings"

Gemtext_Kind :: enum {
	Empty,
	Text,
	Link,
	Heading_1,
	Heading_2,
	Heading_3,
	List,
	Blockquote,
	Preformatting_Delimiter,
}

Gemtext_Link :: struct {
	text: string,
	url: string,
}

Gemtext_Data :: union {
	string,
	Gemtext_Link,
}

Gemtext :: struct {
	kind: Gemtext_Kind,
	data: Gemtext_Data,
}

gemtext_parse :: proc(src: string, preformatted := false) -> Gemtext {
	if !preformatted {
		switch {
		case len(src) == 0:
			return { .Empty, nil }
		case strings.has_prefix(src, ">"):
			return { .Blockquote, src[1:] }
		case strings.has_prefix(src, ">"):
			return { .Blockquote, src[1:] }
		case strings.has_prefix(src, "* "):
			return { .List, src[2:] }
		case strings.has_prefix(src, "```"):
			return { .Preformatting_Delimiter, nil }
		case strings.has_prefix(src, "=>"):
			e: Gemtext
			r := reader_make(strings.trim_space(src[2:]))
			// url := reader_read_delimiter(&r, "\t")
			url  := reader_read_delimiter_whitespace(&r)
			text := url
			if !strings.has_prefix(r.buffer[r.index_curr:], "\r\n") {
				text = reader_read_delimiter(&r, "\r\n")
			}

			e.kind = .Link
			e.data = Gemtext_Link{ text, url }

			return e
		case strings.has_prefix(src, "###"):
			return { .Heading_3, src[3:] }
		case strings.has_prefix(src, "##"):
			return { .Heading_2, src[2:] }
		case strings.has_prefix(src, "#"):
			return { .Heading_1, src[1:] }
		}
	}
	if strings.has_prefix(src, "```") {
		return { .Preformatting_Delimiter, nil }
	}
	return { .Text, src }
}
