package main

import (
	"archive/zip"
	"bytes"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Fake (not real) keys: 32 zero/one bytes in base64.
const k1 = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
const k2 = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE="

const mullvad = `[Interface]
# Device: Test Device
PrivateKey = ` + k1 + `
Address = 10.66.12.34/32,fc00:bbbb:bbbb:bb01::3:c21/128
DNS = 10.64.0.1

[Peer]
PublicKey = ` + k2 + `
AllowedIPs = 0.0.0.0/0,::0/0
Endpoint = 193.32.127.66:51820
`

func TestParseMullvad(t *testing.T) {
	p, err := ParseConfig(mullvad)
	if err != nil {
		t.Fatal(err)
	}
	if len(p.Addresses) != 1 || p.Addresses[0] != "10.66.12.34/32" {
		t.Errorf("addresses: %v", p.Addresses)
	}
	if len(p.DNS) != 1 || p.DNS[0] != "10.64.0.1" {
		t.Errorf("dns: %v", p.DNS)
	}
	if len(p.Routes) != 1 || p.Routes[0] != "0.0.0.0/0" {
		t.Errorf("routes: %v", p.Routes)
	}
	if p.MTU != 1420 {
		t.Errorf("mtu %d", p.MTU)
	}
	if strings.Contains(p.SetConf, "DNS") || strings.Contains(p.SetConf, "Address") {
		t.Errorf("setconf leaked wg-quick keys:\n%s", p.SetConf)
	}
	if !strings.Contains(p.SetConf, "PrivateKey = "+k1) || !strings.Contains(p.SetConf, "Endpoint = 193.32.127.66:51820") {
		t.Errorf("setconf missing fields:\n%s", p.SetConf)
	}
}

func TestKeepaliveAdded(t *testing.T) {
	p, err := ParseConfig(mullvad)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Count(p.SetConf, "PersistentKeepalive = 25") != 1 {
		t.Errorf("keepalive not added once:\n%s", p.SetConf)
	}
	p2, _ := ParseConfig(mullvad + "PersistentKeepalive = 10\n")
	if strings.Contains(p2.SetConf, "= 25") || !strings.Contains(p2.SetConf, "PersistentKeepalive = 10") {
		t.Errorf("explicit keepalive must be kept:\n%s", p2.SetConf)
	}
}

func TestParseCaseAndInlineComments(t *testing.T) {
	in := strings.ReplaceAll(mullvad, "DNS = 10.64.0.1", "dns = 10.64.0.1, 1.1.1.1 # comment")
	in = strings.ReplaceAll(in, "PrivateKey", "privatekey")
	p, err := ParseConfig(in)
	if err != nil {
		t.Fatal(err)
	}
	if len(p.DNS) != 2 {
		t.Errorf("dns: %v", p.DNS)
	}
	if !strings.Contains(p.SetConf, "PrivateKey = ") {
		t.Errorf("key not canonicalised:\n%s", p.SetConf)
	}
}

func TestParseErrors(t *testing.T) {
	cases := map[string]string{
		"bad key":      strings.Replace(mullvad, k1, "notakey", 1),
		"no peer":      "[Interface]\nPrivateKey = " + k1 + "\nAddress = 10.0.0.2/32\n",
		"ipv6 only":    strings.Replace(mullvad, "10.66.12.34/32,", "", 1),
		"unknown key":  mullvad + "Foo = bar\n",
		"unknown sect": "[Nope]\n",
		"no equals":    "[Interface]\nhello\n",
	}
	for name, in := range cases {
		if _, err := ParseConfig(in); err == nil {
			t.Errorf("%s: expected an error", name)
		}
	}
}

func TestSanitizeID(t *testing.T) {
	cases := map[string]string{
		"pt-lis-wg-001.conf": "pt-lis-wg-001",
		"My Server (1).conf": "my-server-1",
		"../../etc/passwd":   "etc-passwd",
		"???":                "",
	}
	for in, want := range cases {
		if got := SanitizeID(in); got != want {
			t.Errorf("SanitizeID(%q)=%q want %q", in, got, want)
		}
	}
}

func TestImportAndPrepare(t *testing.T) {
	base := t.TempDir()
	res := importAny(base, "pt-lis-wg-001.conf", []byte(mullvad))
	if len(res) != 1 || !res[0].OK {
		t.Fatalf("import: %+v", res)
	}
	dir := filepath.Join(base, "profiles", "pt-lis-wg-001")
	for _, f := range []string{"wg.conf", "address", "dns", "routes", "endpoints", "name", "mtu"} {
		if _, err := os.Stat(filepath.Join(dir, f)); err != nil {
			t.Errorf("missing %s", f)
		}
	}
	st, _ := os.Stat(filepath.Join(dir, "wg.conf"))
	if st.Mode().Perm() != 0600 {
		t.Errorf("wg.conf perms %v", st.Mode().Perm())
	}
	out := filepath.Join(t.TempDir(), "run")
	if err := Prepare(base, "pt-lis-wg-001", out); err != nil {
		t.Fatal(err)
	}
	eps, _ := os.ReadFile(filepath.Join(out, "endpoints"))
	if strings.TrimSpace(string(eps)) != "193.32.127.66 51820" {
		t.Errorf("endpoints: %q", eps)
	}
	if err := Prepare(base, "../x", out); err == nil {
		t.Error("path traversal accepted")
	}
}

func TestPrepareResolvesLocalhost(t *testing.T) {
	base := t.TempDir()
	in := strings.Replace(mullvad, "193.32.127.66", "localhost", 1)
	if r := importAny(base, "lh.conf", []byte(in)); !r[0].OK {
		t.Fatal(r[0].Error)
	}
	out := t.TempDir()
	if err := Prepare(base, "lh", out); err != nil {
		t.Skip("no resolver for localhost here:", err)
	}
	b, _ := os.ReadFile(filepath.Join(out, "wg.setconf"))
	if !strings.Contains(string(b), "Endpoint = 127.0.0.1:51820") {
		t.Errorf("not resolved:\n%s", b)
	}
}

func TestZip(t *testing.T) {
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for _, n := range []string{"pt-lis-wg-001.conf", "es-mad-wg-002.conf", "__MACOSX/x.conf", "readme.txt"} {
		w, _ := zw.Create(n)
		w.Write([]byte(mullvad))
	}
	w, _ := zw.Create("broken.conf")
	w.Write([]byte("[Interface]\nhello"))
	zw.Close()

	base := t.TempDir()
	res := importAny(base, "mullvad.zip", buf.Bytes())
	ok, bad := 0, 0
	for _, r := range res {
		if r.OK {
			ok++
		} else {
			bad++
		}
	}
	if ok != 2 || bad != 1 {
		t.Errorf("ok=%d bad=%d: %+v", ok, bad, res)
	}
	if countProfiles(base) != 2 {
		t.Errorf("profiles on disk: %d", countProfiles(base))
	}
}

func upload(t *testing.T, srv *httptest.Server, token string, cookie *http.Cookie, names ...string) (*http.Response, []byte) {
	var body bytes.Buffer
	mw := multipart.NewWriter(&body)
	mw.WriteField("token", token)
	for _, n := range names {
		fw, _ := mw.CreateFormFile("conf", n)
		fw.Write([]byte(mullvad))
	}
	mw.Close()
	req, _ := http.NewRequest("POST", srv.URL+"/upload", &body)
	req.Header.Set("Content-Type", mw.FormDataContentType())
	if cookie != nil {
		req.AddCookie(cookie)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var b bytes.Buffer
	b.ReadFrom(resp.Body)
	return resp, b.Bytes()
}

func TestUploadServer(t *testing.T) {
	os.Setenv("WGTV_BASE", t.TempDir())
	defer os.Unsetenv("WGTV_BASE")
	token, session = "abcd1234", "sess"
	failedAttempts = 0

	srv := httptest.NewServer(http.HandlerFunc(uploadHandler))
	defer srv.Close()

	// wrong code
	if r, _ := upload(t, srv, "nope", nil, "a.conf"); r.StatusCode != http.StatusForbidden {
		t.Errorf("wrong code status %d", r.StatusCode)
	}
	// right code, two files at once
	r, body := upload(t, srv, "abcd1234", nil, "a.conf", "b.conf")
	if r.StatusCode != 200 || strings.Count(string(body), `"ok":true`) != 2 {
		t.Fatalf("status %d body %s", r.StatusCode, body)
	}
	if len(r.Cookies()) == 0 {
		t.Fatal("no session cookie")
	}
	// second upload with cookie only, no code
	r2, body2 := upload(t, srv, "", r.Cookies()[0], "c.conf")
	if r2.StatusCode != 200 || !strings.Contains(string(body2), `"ok":true`) {
		t.Errorf("cookie upload: %d %s", r2.StatusCode, body2)
	}
	if n := countProfiles(os.Getenv("WGTV_BASE")); n != 3 {
		t.Errorf("profiles: %d", n)
	}
}
