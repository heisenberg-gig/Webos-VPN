// wgtv is the helper binary of WebOS VPN. It does the parts that are awkward
// in shell: parsing wg-quick files, importing many of them (also from the ZIP
// that Mullvad offers), resolving endpoints and serving the temporary upload
// page on the LAN.
package main

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	maxFailedAttempts = 5
	maxBody           = 8 << 20
	maxConf           = 64 << 10
	maxZipEntries     = 400
	maxProfiles       = 500
)

func contextWithTimeout(d time.Duration) (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.Background(), d)
}

func baseDir() string {
	if b := os.Getenv("WGTV_BASE"); b != "" {
		return b
	}
	return "/var/lib/webosbrew/webosvpn"
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: wgtv serve | import <file>... | prepare <id> <outdir>")
		os.Exit(2)
	}
	switch os.Args[1] {
	case "serve":
		serve()
	case "import":
		code := 0
		for _, f := range os.Args[2:] {
			data, err := os.ReadFile(f)
			if err != nil {
				fmt.Println("ERROR", f, err)
				code = 1
				continue
			}
			for _, r := range importAny(baseDir(), path.Base(f), data) {
				if r.OK {
					fmt.Println("OK", r.ID)
				} else {
					fmt.Println("ERROR", r.File, r.Error)
					code = 1
				}
			}
		}
		os.Exit(code)
	case "prepare":
		if len(os.Args) != 4 {
			fmt.Fprintln(os.Stderr, "usage: wgtv prepare <id> <outdir>")
			os.Exit(2)
		}
		if err := Prepare(baseDir(), os.Args[2], os.Args[3]); err != nil {
			fmt.Fprintln(os.Stderr, "ERROR:", err)
			os.Exit(1)
		}
	default:
		fmt.Fprintln(os.Stderr, "unknown command:", os.Args[1])
		os.Exit(2)
	}
}

// Result is one line of the upload report.
type Result struct {
	File  string `json:"file"`
	OK    bool   `json:"ok"`
	ID    string `json:"id,omitempty"`
	Name  string `json:"name,omitempty"`
	Error string `json:"error,omitempty"`
}

func countProfiles(base string) int {
	entries, _ := os.ReadDir(base + "/profiles")
	n := 0
	for _, e := range entries {
		if e.IsDir() && !strings.HasPrefix(e.Name(), ".") {
			n++
		}
	}
	return n
}

// importAny imports a .conf or every .conf inside a .zip.
func importAny(base, name string, data []byte) []Result {
	lower := strings.ToLower(name)
	if strings.HasSuffix(lower, ".zip") {
		return importZip(base, name, data)
	}
	return []Result{importOne(base, name, data)}
}

func importOne(base, name string, data []byte) Result {
	r := Result{File: name}
	if len(data) > maxConf {
		r.Error = "file too large"
		return r
	}
	if countProfiles(base) >= maxProfiles {
		r.Error = "too many profiles"
		return r
	}
	p, err := ImportConf(base, name, data)
	if err != nil {
		r.Error = err.Error()
		return r
	}
	r.OK, r.ID, r.Name = true, p.ID, p.Name
	return r
}

func importZip(base, zipName string, data []byte) []Result {
	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return []Result{{File: zipName, Error: "not a valid zip file"}}
	}
	if len(zr.File) > maxZipEntries {
		return []Result{{File: zipName, Error: "zip has too many files"}}
	}
	var out []Result
	var total int64
	for _, f := range zr.File {
		n := path.Base(f.Name)
		if f.FileInfo().IsDir() || strings.HasPrefix(f.Name, "__MACOSX") ||
			strings.HasPrefix(n, ".") || !strings.HasSuffix(strings.ToLower(n), ".conf") {
			continue
		}
		if f.UncompressedSize64 > maxConf {
			out = append(out, Result{File: n, Error: "file too large"})
			continue
		}
		total += int64(f.UncompressedSize64)
		if total > maxBody {
			out = append(out, Result{File: n, Error: "zip is too large when unpacked"})
			break
		}
		rc, err := f.Open()
		if err != nil {
			out = append(out, Result{File: n, Error: err.Error()})
			continue
		}
		b, err := io.ReadAll(io.LimitReader(rc, maxConf+1))
		rc.Close()
		if err != nil {
			out = append(out, Result{File: n, Error: err.Error()})
			continue
		}
		out = append(out, importOne(base, n, b))
	}
	if len(out) == 0 {
		out = append(out, Result{File: zipName, Error: "no .conf files inside the zip"})
	}
	return out
}

// ---- upload server --------------------------------------------------------

var (
	token          string
	session        string
	server         *http.Server
	failedAttempts int
	mu             sync.Mutex
	shutdownOnce   sync.Once
)

func randomHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		log.Fatalf("random: %v", err)
	}
	return hex.EncodeToString(b)
}

func serve() {
	token = os.Getenv("WGTV_TOKEN")
	if token == "" {
		token = randomHex(4)
	}
	session = randomHex(16)
	if tf := os.Getenv("WGTV_TOKEN_FILE"); tf != "" {
		if err := os.WriteFile(tf, []byte(token+"\n"), 0600); err != nil {
			log.Fatalf("write token file: %v", err)
		}
		defer os.Remove(tf)
	}
	timeout := 10 * time.Minute
	if raw := os.Getenv("WGTV_TIMEOUT"); raw != "" {
		if s, err := strconv.Atoi(raw); err == nil && s > 0 {
			timeout = time.Duration(s) * time.Second
		}
	}
	port := os.Getenv("WGTV_PORT")
	if port == "" {
		port = "8088"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", pageHandler)
	mux.HandleFunc("/upload", uploadHandler)
	mux.HandleFunc("/done", doneHandler)
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) { fmt.Fprintln(w, "OK") })

	server = &http.Server{
		Addr:              ":" + port,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       60 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       30 * time.Second,
	}
	log.Printf("wgtv upload server on :%s, expires after %s", port, timeout)
	time.AfterFunc(timeout, func() { shutdownServer("timeout reached") })
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
}

func shutdownServer(reason string) {
	shutdownOnce.Do(func() {
		go func() {
			time.Sleep(300 * time.Millisecond)
			log.Printf("stopping upload server: %s", reason)
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()
			if server != nil {
				_ = server.Shutdown(ctx)
			}
		}()
	})
}

func pageHandler(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	io.WriteString(w, pageHTML)
}

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func sessionOK(r *http.Request) bool {
	c, err := r.Cookie("wgtv_session")
	return err == nil && subtle.ConstantTimeCompare([]byte(c.Value), []byte(session)) == 1
}

func uploadHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "method"})
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxBody)
	if err := r.ParseMultipartForm(maxBody); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "badUpload"})
		return
	}
	if !sessionOK(r) {
		got := r.FormValue("token")
		if subtle.ConstantTimeCompare([]byte(got), []byte(token)) != 1 {
			mu.Lock()
			failedAttempts++
			locked := failedAttempts >= maxFailedAttempts
			mu.Unlock()
			if locked {
				writeJSON(w, http.StatusTooManyRequests, map[string]string{"error": "locked"})
				shutdownServer("too many invalid access codes")
				return
			}
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "badCode"})
			return
		}
		http.SetCookie(w, &http.Cookie{Name: "wgtv_session", Value: session, Path: "/", HttpOnly: true, SameSite: http.SameSiteStrictMode})
	}

	var results []Result
	if r.MultipartForm != nil {
		for _, fh := range r.MultipartForm.File["conf"] {
			f, err := fh.Open()
			if err != nil {
				results = append(results, Result{File: fh.Filename, Error: err.Error()})
				continue
			}
			data, err := io.ReadAll(io.LimitReader(f, maxBody))
			f.Close()
			if err != nil {
				results = append(results, Result{File: fh.Filename, Error: err.Error()})
				continue
			}
			results = append(results, importAny(baseDir(), fh.Filename, data)...)
		}
	}
	if len(results) == 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missingFile"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"results": results})
}

func doneHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost || !sessionOK(r) {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "badCode"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
	shutdownServer("finished by user")
}
