package gemreq

import "core:fmt"
import "core:math"
import "core:strings"
import "vendor:raylib"

env_history_navigate_absolute :: proc(env: ^Environment, url: string, history_append := true, allocator := context.allocator) -> (ok: bool) {
	host, port, path, url_ok := gemini_parse_url(url)
	if !url_ok {
		env.error = strings.clone_to_cstring("failed parsing url", allocator)
		return false
	}
	return env_history_navigate_endpoint(env, { host = host, path = path, port = port }, history_append, allocator)
}

env_history_navigate_relative :: proc(env: ^Environment, path: string, history_append := true, allocator := context.allocator) -> (ok: bool) {
	assert(env.document_is_loaded, "calling env_history_navigate_path without a parent document")

	endpoint := env_endpoint(env)
	endpoint.host = strings.clone(endpoint.host, allocator)
	endpoint.path = strings.clone(path, allocator)
	return env_history_navigate_endpoint(env, endpoint, history_append, allocator)
}

env_history_navigate_link :: proc(env: ^Environment, element: Gemini_Element_Link) {
	url := element.url
	if strings.has_prefix(url, "https://") do fmt.eprintfln("gemreq: todo!: HTTPS links are not supported %s", url)
	else if strings.has_prefix(url, "gopher://") do fmt.eprintfln("gemreq: todo!: Gopher links are not supported %s", url)
	else if strings.has_prefix(url, "gemini://") do env_history_navigate_absolute(env, url)
	else if strings.has_prefix(url, "/") do env_history_navigate_relative(env, url)
	else {
		// BUG(XENOBAS): navigating from .../docs/faq.gmi -> faq-section-4.gmi
		// results in .../docs/faq.gmifaq-section-4.gmi
		endpoint := env_endpoint(env)

		path := strings.join({ endpoint.path, url }, "")
		defer delete(path)

		env_history_navigate_relative(env, path)
	}
}

env_history_navigate_endpoint :: proc(env: ^Environment, endpoint: Gemini_Endpoint, history_append := true, allocator := context.allocator) -> (ok: bool) {
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
	env.scroll_target = 0

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
		return env_history_navigate_absolute(env, location, false, allocator)
	}
	return true
}

env_history_pop :: proc(env: ^Environment) {
	if len(env.history) > 1 {
		endpoint_delete(pop(&env.history))
		endpoint := env_endpoint(env)
		env_history_navigate_endpoint(env, endpoint, false)
	}
}
