package gemini

import "core:fmt"
import "core:math"
import "core:strings"
import "vendor:raylib"

Environment :: struct {
	fonts: Font_Group,
	document: Gemini_Document,
	document_is_loaded: bool,
	element_active: Maybe(Gemini_Element),
	history: [dynamic]Gemini_Endpoint,
	error: Gemini_Error
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

env_endpoint :: proc(env: ^Environment) -> Gemini_Endpoint {
	assert(len(env.history) > 0, "calling env_endpoint without a history")
	return env.history[len(env.history) - 1]
}

env_navigate_absolute :: proc(env: ^Environment, url: string, history_append := true, allocator := context.allocator) -> (ok: bool) {
	host, port, path, url_ok := gemini_parse_url(url)
	if !url_ok {
		env.error = strings.clone_to_cstring("failed parsing url", allocator)
		return false
	}
	return env_navigate_endpoint(env, { host = host, path = path, port = port }, history_append, allocator)
}

env_navigate_relative :: proc(env: ^Environment, path: string, history_append := true, allocator := context.allocator) -> (ok: bool) {
	assert(env.document_is_loaded, "calling env_navigate_path without a parent document")

	endpoint := env_endpoint(env)
	endpoint.host = strings.clone(endpoint.host, allocator)
	endpoint.path = strings.clone(path, allocator)
	return env_navigate_endpoint(env, endpoint, history_append, allocator)
}

env_navigate_endpoint :: proc(env: ^Environment, endpoint: Gemini_Endpoint, history_append := true, allocator := context.allocator) -> (ok: bool) {
	fmt.printfln("gemreq: attempting navigating to %s:%d%s", endpoint.host, endpoint.port, endpoint.path)

	// Cleanup previous navigation
	if env.document_is_loaded do gemini_delete(&env.document)
	env.document_is_loaded = false

	// Send a Gemini request
	bytes, error_fetch := gemini_fetch(endpoint.host, endpoint.port, endpoint.path, allocator)
	if error_fetch != nil {
		fmt.eprintfln("gemreq: error during fetch %v", error_fetch)
		env.error = error_fetch
		return false
	}
	defer delete(bytes)

	if history_append do append(&env.history, endpoint)

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
		return env_navigate_absolute(env, location, false, allocator)
	}
	return true
}

env_history_pop :: proc(env: ^Environment) {
	if len(env.history) > 1 {
		endpoint_delete(pop(&env.history))
		endpoint := env_endpoint(env)
		env_navigate_endpoint(env, endpoint, false)
	}
}
