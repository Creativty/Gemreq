package gemreq

import "openssl"

import "core:c"
import "core:io"
import "core:os"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:net"
import "core:bufio"
import "core:bytes"
import "core:strings"
import "core:strconv"

gemini_status_to_text :: proc(status: Gemini_Status) -> string {
	switch status {
	case .Unreachable: return "Unreachable"
	case .Input_Expected: return "Input expected"
	case .Input_Sensitive: return "Input sensitive"
	case .Success: return "Success"
	case .Redirect_Temporary: return "Redirect temporary"
	case .Redirect_Permanent: return "Redirect permanent"
	case .Failure_Temporary: return "Temporary failure"
	case .Failure_Temporary_Server_Unavailable: return "Server unavailable"
	case .Failure_Temporary_CGI: return "CGI failure"
	case .Failure_Temporary_Proxy: return "Proxy failure"
	case .Failure_Temporary_Slow_Down: return "Slow down"
	case .Failure_Permanent: return "Server error"
	case .Failure_Permanent_Not_Found: return "Not found"
	case .Failure_Permanent_Gone: return "Gone"
	case .Failure_Permanent_Proxy_Request_Refused: return "Proxy request refused"
	case .Failure_Permanent_Bad_Request: return "Bad request"
	case .Client_Certificate: return "Client certificate"
	case .Client_Certificate_Not_Authorized: return "Unauthorized certificate"
	case .Client_Certificate_Not_Valid: return "Invalid certificate"
	case:
		return ""
	}
}

gemini_status_to_description :: proc(status: Gemini_Status) -> string {
	switch status {
	case .Unreachable: return "Application bug, this error state should be unreachable, please check the logs."
	case .Input_Expected: return "The basic input status code. A client MUST prompt a user for input, it should be URI-encoded per [STD66] and sent as a query to the same URI that generated this response."
	case .Input_Sensitive: return "As per status code 10, but for use with sensitive input such as passwords. Clients should present the prompt as per status code 10, but the user's input should not be echoed to the screen to prevent it being read by \"shoulder surfers\"."
	case .Success: return "The server has successfully parsed and understood the request, and will serve up content of the given MIME type. "
	case .Redirect_Temporary: return "The basic redirection code. The redirection is temporary and the client should continue to request the content with the original URI."
	case .Redirect_Permanent: return "The location of the content has moved permanently to a new location, and clients SHOULD use the new location to retrieve the given content from then on."
	case .Failure_Temporary: return "An unspecified condition exists on the server that is preventing the content from being served, but a client can try again to obtain the content."
	case .Failure_Temporary_Server_Unavailable: return "The server is unavailable due to overload or maintenance. (cf HTTP 503)"
	case .Failure_Temporary_CGI: return "A CGI process, or similar system for generating dynamic content, died unexpectedly or timed out."
	case .Failure_Temporary_Proxy: return "A proxy request failed because the server was unable to successfully complete a transaction with the remote host. (cf HTTP 502, 504)"
	case .Failure_Temporary_Slow_Down: return "The server is requesting the client to slow down requests, and SHOULD use an exponential back off, where subsequent delays between requests are doubled until this status no longer returned."
	case .Failure_Permanent: return "This is the general permanent failure code."
	case .Failure_Permanent_Not_Found: return "The requested resource could not be found (you can't find things at Area 51) and no further information is available. It may exist in the future, it may not. Who knows?"
	case .Failure_Permanent_Gone: return "The resource requested is no longer available and will not be available again. Search engines and similar tools should remove this resource from their indices. Content aggregators should stop requesting the resource and convey to their human users that the subscribed resource is gone. (cf HTTP 410)"
	case .Failure_Permanent_Proxy_Request_Refused: return "The request was for a resource at a domain not served by the server and the server does not accept proxy requests."
	case .Failure_Permanent_Bad_Request: return "The server was unable to parse the client's request, presumably due to a malformed request, or the request violated the constraints listed in the Request section."
	case .Client_Certificate: return "The content requires a client certificate."
	case .Client_Certificate_Not_Authorized: return "The supplied client certificate is not authorised for accessing the particular requested resource. The problem is not with the certificate itself, which may be authorised for other resources."
	case .Client_Certificate_Not_Valid: return "The supplied client certificate was not accepted because it is not valid. This indicates a problem with the certificate in and of itself, with no consideration of the particular requested resource. The most likely cause is that the certificate's validity start date is in the future or its expiry date has passed, but this code may also indicate an invalid signature, or a violation of a X509 standard requirements."
	case:
		return ""
	}
}
