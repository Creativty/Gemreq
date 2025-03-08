package gemreq

import "core:fmt"

navigate_click :: proc(browser: ^Browser, url: string) {
	browser.navigate_queue = url
}

navigate_string :: proc(browser: ^Browser, url: string) {
	// TODO(XENOBAS): move this into its own thread
	omnibar := &browser.omnibar

	omnibar.disabled = true
	defer omnibar.disabled = false

	if error_string, error_present := omnibar.error.(cstring); error_present {
		delete(error_string)
		omnibar.error = nil
	}

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

navigate_endpoint :: proc(browser: ^Browser, ep: Endpoint, edit_history := false) {
	omnibar := &browser.omnibar

	omnibar.disabled = true
	defer omnibar.disabled = false

	if error_string, error_present := omnibar.error.(cstring); error_present {
		delete(error_string)
		omnibar.error = nil
	}

	if edit_history {
		if ep_old, ep_old_present := browser.endpoint.(Endpoint); ep_old_present {
			delete_endpoint(ep_old)
		}
		browser.endpoint = ep
	}

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

navigate :: proc {
	navigate_string,
	navigate_endpoint,
}
