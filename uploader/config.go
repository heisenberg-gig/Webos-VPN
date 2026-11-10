package main

import (
	"bufio"
	"encoding/base64"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Profile is a parsed wg-quick configuration, reduced to what `wg setconf`
// understands plus the extra fields the shell scripts need.
type Profile struct {
	ID        string
	Name      string
	Addresses []string // IPv4 CIDRs for the tunnel interface
	DNS       []string // IPv4 resolvers from the DNS= line
	MTU       int
	Endpoints []string // host:port, as written in the file
	Routes    []string // IPv4 AllowedIPs
	SetConf   string   // text accepted by `wg setconf`
}

var idRe = regexp.MustCompile(`[^a-z0-9._-]+`)

// SanitizeID turns a file name into a safe directory name.
func SanitizeID(name string) string {
	name = strings.ToLower(strings.TrimSpace(name))
	name = strings.TrimSuffix(name, ".conf")
	name = idRe.ReplaceAllString(name, "-")
	name = strings.Trim(name, "-._")
	if len(name) > 48 {
		name = name[:48]
	}
	return name
}

func stripComment(s string) string {
	if i := strings.Index(s, "#"); i >= 0 {
		s = s[:i]
	}
	return strings.TrimSpace(s)
}

func splitList(v string) []string {
	var out []string
	for _, p := range strings.Split(v, ",") {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

func validKey(k string) bool {
	b, err := base64.StdEncoding.DecodeString(k)
	return err == nil && len(b) == 32
}

// ParseConfig converts wg-quick text into a Profile.
func ParseConfig(input string) (*Profile, error) {
	p := &Profile{MTU: 1420}
	section := ""
	var setconf []string
	peers := 0
	hasPrivate := false
	peerHasKey := false

	sc := bufio.NewScanner(strings.NewReader(input))
	sc.Buffer(make([]byte, 0, 64*1024), 256*1024)
	for sc.Scan() {
		line := stripComment(strings.TrimRight(sc.Text(), "\r"))
		if line == "" {
			continue
		}
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			section = strings.ToLower(strings.TrimSpace(line[1 : len(line)-1]))
			switch section {
			case "interface":
			case "peer":
				if peers > 0 && !peerHasKey {
					return nil, errors.New("a [Peer] without PublicKey")
				}
				peers++
				peerHasKey = false
			default:
				return nil, fmt.Errorf("unknown section: %s", line)
			}
			setconf = append(setconf, "", "["+titleSection(section)+"]")
			continue
		}
		if section == "" {
			return nil, fmt.Errorf("line outside any section: %s", line)
		}
		kv := strings.SplitN(line, "=", 2)
		if len(kv) != 2 {
			return nil, fmt.Errorf("unrecognised line: %s", line)
		}
		key := strings.TrimSpace(kv[0])
		val := strings.TrimSpace(kv[1])
		lk := strings.ToLower(key)

		if section == "interface" {
			switch lk {
			case "address":
				for _, a := range splitList(val) {
					if strings.Contains(a, ":") {
						continue // IPv6 is not routed by this app
					}
					if _, _, err := net.ParseCIDR(a); err != nil {
						return nil, fmt.Errorf("invalid Address: %s", a)
					}
					p.Addresses = append(p.Addresses, a)
				}
				continue
			case "dns":
				for _, d := range splitList(val) {
					if ip := net.ParseIP(d); ip != nil && ip.To4() != nil {
						p.DNS = append(p.DNS, d)
					}
				}
				continue
			case "mtu":
				if n, err := strconv.Atoi(val); err == nil && n >= 1280 && n <= 1500 {
					p.MTU = n
				}
				continue
			case "table", "saveconfig", "preup", "postup", "predown", "postdown":
				continue
			case "privatekey":
				if !validKey(val) {
					return nil, errors.New("PrivateKey is not a valid WireGuard key")
				}
				hasPrivate = true
			case "listenport", "fwmark":
			default:
				return nil, fmt.Errorf("unsupported key: %s", key)
			}
			setconf = append(setconf, canonical(lk)+" = "+val)
			continue
		}

		// [Peer]
		switch lk {
		case "publickey":
			if !validKey(val) {
				return nil, errors.New("PublicKey is not a valid WireGuard key")
			}
			peerHasKey = true
		case "presharedkey":
			if !validKey(val) {
				return nil, errors.New("PresharedKey is not a valid WireGuard key")
			}
		case "allowedips":
			for _, r := range splitList(val) {
				if strings.Contains(r, ":") {
					continue
				}
				if _, _, err := net.ParseCIDR(r); err != nil {
					return nil, fmt.Errorf("invalid AllowedIPs entry: %s", r)
				}
				p.Routes = append(p.Routes, r)
			}
		case "endpoint":
			if _, _, err := net.SplitHostPort(val); err != nil {
				return nil, fmt.Errorf("invalid Endpoint: %s", val)
			}
			p.Endpoints = append(p.Endpoints, val)
		case "persistentkeepalive":
		default:
			return nil, fmt.Errorf("unsupported key: %s", key)
		}
		setconf = append(setconf, canonical(lk)+" = "+val)
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	if !hasPrivate {
		return nil, errors.New("PrivateKey not found")
	}
	if peers == 0 || !peerHasKey {
		return nil, errors.New("no [Peer] with a PublicKey")
	}
	if len(p.Addresses) == 0 {
		return nil, errors.New("no IPv4 Address in [Interface]")
	}
	if len(p.Routes) == 0 {
		return nil, errors.New("no IPv4 AllowedIPs in [Peer]")
	}
	p.SetConf = strings.TrimSpace(strings.Join(ensureKeepalive(setconf), "\n")) + "\n"
	return p, nil
}

// ensureKeepalive adds PersistentKeepalive = 25 to every [Peer] that lacks it.
// Mullvad files do not set it; without it the first handshake only happens when
// traffic is sent, and NAT mappings on the home router can expire while the TV
// is idle.
func ensureKeepalive(lines []string) []string {
	var out []string
	inPeer, has := false, false
	flush := func() {
		if inPeer && !has {
			out = append(out, "PersistentKeepalive = 25")
		}
	}
	for _, l := range lines {
		if strings.HasPrefix(l, "[") {
			flush()
			inPeer = l == "[Peer]"
			has = false
		}
		if strings.HasPrefix(l, "PersistentKeepalive") {
			has = true
		}
		out = append(out, l)
	}
	flush()
	return out
}

func titleSection(s string) string {
	if s == "interface" {
		return "Interface"
	}
	return "Peer"
}

var canon = map[string]string{
	"privatekey": "PrivateKey", "listenport": "ListenPort", "fwmark": "FwMark",
	"publickey": "PublicKey", "presharedkey": "PresharedKey", "allowedips": "AllowedIPs",
	"endpoint": "Endpoint", "persistentkeepalive": "PersistentKeepalive",
}

func canonical(lk string) string { return canon[lk] }

func writeLines(path string, lines []string) error {
	data := ""
	if len(lines) > 0 {
		data = strings.Join(lines, "\n") + "\n"
	}
	return os.WriteFile(path, []byte(data), 0600)
}

// SaveProfile stores p under base/profiles/<id> atomically.
func SaveProfile(base string, p *Profile) error {
	root := filepath.Join(base, "profiles")
	if err := os.MkdirAll(root, 0700); err != nil {
		return err
	}
	tmp, err := os.MkdirTemp(root, ".tmp-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	if err := os.Chmod(tmp, 0700); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(tmp, "wg.conf"), []byte(p.SetConf), 0600); err != nil {
		return err
	}
	files := map[string][]string{
		"address":   p.Addresses,
		"dns":       p.DNS,
		"routes":    p.Routes,
		"endpoints": p.Endpoints,
		"name":      {p.Name},
		"mtu":       {strconv.Itoa(p.MTU)},
	}
	for name, lines := range files {
		if err := writeLines(filepath.Join(tmp, name), lines); err != nil {
			return err
		}
	}
	dst := filepath.Join(root, p.ID)
	if err := os.RemoveAll(dst); err != nil {
		return err
	}
	return os.Rename(tmp, dst)
}

// ImportConf parses data and saves it. fileName decides the profile id/name.
func ImportConf(base, fileName string, data []byte) (*Profile, error) {
	nameBase := strings.TrimSuffix(filepath.Base(fileName), filepath.Ext(fileName))
	id := SanitizeID(nameBase)
	if id == "" {
		return nil, errors.New("file name has no usable characters")
	}
	p, err := ParseConfig(string(data))
	if err != nil {
		return nil, err
	}
	p.ID = id
	p.Name = strings.TrimSpace(nameBase)
	if err := SaveProfile(base, p); err != nil {
		return nil, err
	}
	return p, nil
}

// Prepare resolves host names in a stored profile and writes the files the
// start script needs: wg.setconf (endpoints as IPs) and endpoints (ip port).
func Prepare(base, id, outDir string) error {
	if id != SanitizeID(id) || id == "" {
		return errors.New("invalid profile id")
	}
	src, err := os.ReadFile(filepath.Join(base, "profiles", id, "wg.conf"))
	if err != nil {
		return err
	}
	var out, eps []string
	for _, line := range strings.Split(string(src), "\n") {
		if !strings.HasPrefix(line, "Endpoint = ") {
			out = append(out, line)
			continue
		}
		host, port, err := net.SplitHostPort(strings.TrimPrefix(line, "Endpoint = "))
		if err != nil {
			return err
		}
		ip := net.ParseIP(host)
		if ip == nil {
			r := net.Resolver{}
			ctxIPs, err := lookupV4(&r, host)
			if err != nil {
				return fmt.Errorf("cannot resolve %s: %v", host, err)
			}
			ip = ctxIPs
		}
		if ip.To4() == nil {
			return fmt.Errorf("endpoint %s is IPv6-only, which is not supported", host)
		}
		out = append(out, "Endpoint = "+ip.String()+":"+port)
		eps = append(eps, ip.String()+" "+port)
	}
	if err := os.MkdirAll(outDir, 0700); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(outDir, "wg.setconf"), []byte(strings.Join(out, "\n")), 0600); err != nil {
		return err
	}
	return writeLines(filepath.Join(outDir, "endpoints"), eps)
}

func lookupV4(r *net.Resolver, host string) (net.IP, error) {
	ctx, cancel := contextWithTimeout(8 * time.Second)
	defer cancel()
	ips, err := r.LookupIPAddr(ctx, host)
	if err != nil {
		return nil, err
	}
	for _, a := range ips {
		if a.IP.To4() != nil {
			return a.IP, nil
		}
	}
	return nil, errors.New("no IPv4 address")
}
