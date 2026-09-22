package main

import "net/http"

// withSecurityHeaders sets response headers that used to come from
// CloudFront's response-headers policy, which no longer exists (ADR-025) -
// an ALB cannot rewrite headers on forwarded traffic, only on its own
// fixed-response actions, so these move into the app instead.
//
// Strict-Transport-Security is deliberately not set here. HSTS tells a
// browser to use HTTPS only for this host from now on; the ALB has no HTTPS
// listener (ADR-025's accepted trade-off), so sending it would be actively
// wrong, not a smaller version of the same protection.
func withSecurityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "same-origin")
		next.ServeHTTP(w, r)
	})
}
