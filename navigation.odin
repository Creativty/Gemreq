package gemreq

import "core:fmt"
import "core:log"
import "core:sync/chan"

navigate_click :: proc(browser: ^Browser, url: string) {
	browser.navigate_queue = url
}

navigate_string :: proc(browser: ^Browser, url: string) {
	endpoint, _ := resolve_endpoint(browser, url)
	endpoint_sent := chan.send(browser.channels.request, endpoint)
	if !endpoint_sent do log.panicf("failure: could not send endpoint to networking thread")
}

navigate_endpoint :: proc(browser: ^Browser, ep: Endpoint, edit_history := false) {
	endpoint_sent := chan.send(browser.channels.request, ep)
	if !endpoint_sent do log.panicf("failure: could not send endpoint to networking thread")
}

navigate :: proc {
	navigate_string,
	navigate_endpoint,
}
