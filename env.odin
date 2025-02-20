package gemini

import "core:fmt"
import "core:math"
import "core:strings"
import "vendor:raylib"

Gemini_Endpoint :: struct {
	port: int,
	host: string,
	path: string,
}

Environment :: struct {
	fonts: Font_Group,
	endpoint: Gemini_Endpoint,
	document: Gemini_Document,
	document_is_loaded: bool,
	element_active: Maybe(Gemini_Element),
	error: Gemini_Error
}

gemini_endpoint_delete :: proc(endpoint: Gemini_Endpoint) {
	delete(endpoint.host)
	delete(endpoint.path)
}

env_navigate :: proc(env: ^Environment, url: string, allocator := context.allocator) -> (ok: bool) {
	hostname, port, path, url_ok := gemini_parse_url(url)
	if !url_ok {
		env.error = strings.clone_to_cstring("failed parsing url", allocator)
		return false
	}
	return _env_navigate(env, hostname, path, port, allocator)
}

env_navigate_path :: proc(env: ^Environment, path: string, allocator := context.allocator) -> (ok: bool) {
	assert(env.document_is_loaded, "calling env_navigate_path without a parent document")

	host := strings.clone(env.endpoint.host, allocator)
	path := strings.clone(path, allocator)
	return _env_navigate(env, host, path, env.endpoint.port, allocator)
}

_env_navigate :: proc(env: ^Environment, host: string, path: string, port: int, allocator := context.allocator) -> (ok: bool) {
	fmt.printfln("gemreq: attempting navigating to %s:%d%s", host, port, path)

	// Cleanup previous navigation
	if env.document_is_loaded {
		gemini_endpoint_delete(env.endpoint)
		gemini_delete(&env.document)
	}
	env.document_is_loaded = false

	env.endpoint.port = port
	env.endpoint.path = path
	env.endpoint.host = host

	// Send a Gemini request
	bytes, error_fetch := gemini_fetch(env.endpoint.host, env.endpoint.port, env.endpoint.path, allocator)
	if error_fetch != nil {
		fmt.eprintfln("gemreq: error during fetch %v", error_fetch)
		env.error = error_fetch
		return false
	}
	defer delete(bytes)

	// Parse the Gemini document for display
	document, error_parse := gemini_parse(bytes)
	if error_parse != nil {
		fmt.eprintfln("gemreq: error during parsing %v", error_parse)
		env.error = error_parse
		return false
	}
	env.document = document
	env.document_is_loaded = true

	if gemini_status_is_redirect(document.status) && document.location != nil {
		location := document.location.(string)
		return env_navigate(env, location, allocator)
	}
	return true
}

env_load_fonts :: proc(env: ^Environment) {
	using raylib

	font_size := i32(math.floor(HEIGHT_CHAR))
	env.fonts[.Normal][.Paragraph] = LoadFontEx("font/ttf/DejaVuSerif.ttf", font_size, nil, -1)
	env.fonts[.Bold][.Paragraph] = LoadFontEx("font/ttf/DejaVuSerif-Bold.ttf", font_size, nil, -1)
	env.fonts[.Bold][.Heading] = LoadFontEx("font/ttf/DejaVuSerif-Bold.ttf", i32(f32(font_size) * CHAR_FACTOR_HEADING), nil, -1)
}

env_unload_fonts :: proc(env: ^Environment) {
	using raylib

	UnloadFont(env.fonts[.Normal][.Paragraph])
	UnloadFont(env.fonts[.Bold][.Paragraph])
	UnloadFont(env.fonts[.Bold][.Heading])
}
