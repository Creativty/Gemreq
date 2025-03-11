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

	when false {
		omnibar := &browser.omnibar

		omnibar.disabled = true
		defer omnibar.disabled = false

		// Omnibar error clear
		if error_string, error_present := omnibar.error.(cstring); error_present {
			delete(error_string)
			omnibar.error = nil
		}

		// History
		if ep_old, ep_old_present := browser.endpoint.(Endpoint); ep_old_present {
			delete_endpoint(ep_old)
		}
		ep := parse_endpoint(url)
		browser.endpoint = ep

		resp, err := request_document(ep)
		if err != nil {
			omnibar.error = fmt.caprintf("%v", err)
			return
		}
		
		document := parse_document(browser, resp)

		if doc_old, doc_exists := browser.document.(Document); doc_exists {
			browser.scroll.target = 0
			browser.scroll.current = 0
			delete_document(doc_old)
		}
		browser.document = document
		omnibar.visible = false
	}
}

navigate_endpoint :: proc(browser: ^Browser, ep: Endpoint, edit_history := false) {
	endpoint_sent := chan.send(browser.channels.request, ep)
	if !endpoint_sent do log.panicf("failure: could not send endpoint to networking thread")
}

navigate :: proc {
	navigate_string,
	navigate_endpoint,
}
