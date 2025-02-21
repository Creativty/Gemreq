package gemini

Gemini_Endpoint :: struct {
	port: int,
	host: string,
	path: string,
}

endpoint_delete :: proc(endpoint: Gemini_Endpoint) {
	delete(endpoint.host)
	delete(endpoint.path)
}
