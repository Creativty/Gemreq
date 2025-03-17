package uri

import "core:log"
import "core:testing"

@(test)
test_parse :: proc(t: ^testing.T) {
	// parse :: proc(source: string) -> (uri: URI, ok: bool)
	scheme_empty, scheme_empty_ok := parse("")
	defer destroy(scheme_empty)
	testing.expect(t, scheme_empty_ok == false, "empty string gave a false positive")

	scheme_news, scheme_news_ok := parse("news:comp.infosystems.www.servers.unix")
	defer destroy(scheme_news)
	testing.expect_value(t, scheme_news_ok, true)
	testing.expect_value(t, scheme_news.scheme, "news")
	testing.expect(t, scheme_news.authority == nil)

	scheme_http, scheme_http_ok := parse("http://localhost:8080/about#contact")
	defer destroy(scheme_http)
	testing.expect_value(t, scheme_http_ok, true)
	testing.expect_value(t, scheme_http.scheme, "http")
	if testing.expect(t, scheme_http.authority != nil) {
		authority := scheme_http.authority.(Authority)
		testing.expect_value(t, authority.host, "localhost")
		testing.expect_value(t, authority.port, "8080")
	}

	host_ipv4_scheme_telnet, host_ipv4_scheme_telnet_ok := parse("telnet://192.0.2.16:80/")
	defer destroy(host_ipv4_scheme_telnet)
	testing.expect_value(t, host_ipv4_scheme_telnet_ok, true)
	testing.expect_value(t, host_ipv4_scheme_telnet.scheme, "telnet")
	if testing.expect(t, host_ipv4_scheme_telnet.authority != nil) {
		authority := host_ipv4_scheme_telnet.authority.(Authority)
		testing.expect_value(t, authority.host, "192.0.2.16")
		testing.expect_value(t, authority.port, "80")
	}

	scheme_tel, scheme_tel_ok := parse("tel:+1-816-555-1212")
	defer destroy(scheme_tel)
	testing.expect_value(t, scheme_tel_ok, true)
	testing.expect_value(t, scheme_tel.scheme, "tel")
	testing.expect_value(t, scheme_tel.authority, nil)

	scheme_https, scheme_https_ok := parse("https://youtube.com:443/watch?v=3b3f9087a")
	defer destroy(scheme_https)
	testing.expect_value(t, scheme_https_ok, true)
	testing.expect_value(t, scheme_https.scheme, "https")
	if testing.expect(t, scheme_https.authority != nil) {
		authority := scheme_https.authority.(Authority)
		testing.expect_value(t, authority.host, "youtube.com")
		testing.expect_value(t, authority.port, "443")
	}

	host_ipv6_scheme_gemini, host_ipv6_scheme_gemini_ok := parse("gemini://[2001:0db8:85a3:0000:0000:8a2e:0370:7334]")
	defer destroy(host_ipv6_scheme_gemini)
	testing.expect_value(t, host_ipv6_scheme_gemini_ok, true)
	testing.expect_value(t, host_ipv6_scheme_gemini.scheme, "gemini")
	if testing.expect(t, host_ipv6_scheme_gemini.authority != nil) {
		authority := host_ipv6_scheme_gemini.authority.(Authority)
		testing.expect_value(t, authority.host, "[2001:0db8:85a3:0000:0000:8a2e:0370:7334]")
		testing.expect_value(t, authority.port, "")
	}

	host_ipv6_unterminated, host_ipv6_unterminated_ok := parse("gemini://[2001:0db8:85a3:0000:0000:8a2e:0370:7334")
	defer destroy(host_ipv6_unterminated)
	testing.expect_value(t, host_ipv6_unterminated_ok, false)
	testing.expect_value(t, host_ipv6_unterminated.scheme, "gemini")
}
