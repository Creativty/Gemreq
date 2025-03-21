package gemreq

import "uri"
import "core:fmt"
import "core:log"
import "core:sync/chan"

navigate_enqueue :: proc(browser: ^Browser, url: string) {
	browser.navigate_queue = url
}

navigate_uri :: proc(browser: ^Browser, location: uri.URI) {
	endpoint, ok := resolve_endpoint(browser, location)
	if ok {
		navigate_endpoint(browser, endpoint)
	} else do log.errorf("could not resolve %#v", location)
}

navigate_string :: proc(browser: ^Browser, text: string) {
	location, ok := uri.parse(text)
	defer uri.destroy(location)
	if ok {
		navigate_uri(browser, location)
	} else do log.errorf("could not parse %#v", text)
}

navigate_endpoint :: proc(browser: ^Browser, ep: Endpoint, edit_history := false) {
	sent := chan.send(browser.channels.request, ep)
	if !sent do log.errorf("failure: could not send endpoint to networking thread")
}

navigate :: proc {
	navigate_uri,
	navigate_string,
	navigate_endpoint,
}
