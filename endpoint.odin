package gemreq

import "core:fmt"

Gemini_Endpoint :: struct {
	port: int,
	host: string,
	path: string,
}

endpoint_delete :: proc(endpoint: Gemini_Endpoint) {
	delete(endpoint.host)
	delete(endpoint.path)
}

endpoint_to_string :: proc(endpoint: Gemini_Endpoint, allocator := context.allocator) -> string {
	return fmt.aprintf("gemini://%s:%d%s", endpoint.host, endpoint.port, endpoint.path, allocator = allocator)
}
