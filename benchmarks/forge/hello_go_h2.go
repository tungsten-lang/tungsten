package main

import (
	"net/http"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Length", "12")
		w.Write([]byte("Hello World\n"))
	})
	http.ListenAndServeTLS(":8443", "/tmp/bench_cert.pem", "/tmp/bench_key.pem", nil)
}
