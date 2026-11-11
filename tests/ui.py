"""Renders the TV UI in Chromium at 1920x1080 against a fake webOS service and
checks the behaviour that matters: what gets sent to the TV, and what the user sees.
Usage: python3 tests/ui.py [--shots]   (screenshots go to tests/shots)"""
import json, re, sys, pathlib
from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "app/com.heisenberg.webosvpn"
SHOTS = ROOT / "tests/shots"
SHOTS.mkdir(exist_ok=True)

IDS = [("pt-lis-wg-001", "pt-lis-wg-001"), ("pt-lis-wg-002", "pt-lis-wg-002"), ("es-mad-wg-001", "es-mad-wg-001"),
       ("de-fra-wg-003", "de-fra-wg-003"), ("se-sto-wg-004", "se-sto-wg-004"), ("nl-ams-wg-005", "nl-ams-wg-005"),
       ("ch-zrh-wg-006", "ch-zrh-wg-006"), ("us-nyc-wg-007", "us-nyc-wg-007"), ("gb-lon-wg-008", "gb-lon-wg-008"),
       ("fr-par-wg-009", "fr-par-wg-009"), ("no-osl-wg-010", "no-osl-wg-010"), ("casa", "Casa do Zé")]

def snapshot(status, profile="", ks="1", autostart="1", profiles=True, last="pt-lis-wg-001", dns_mode="profile", wd_state="watching", wd_count="0", favs=(), autoreconnect="1"):
    st = {"status": status, "profile": profile, "profile_name": profile, "iface": "up" if status in ("connected", "nohandshake", "stale") else "down",
          "handshake_age": "12" if status == "connected" else ("-1" if status == "nohandshake" else "300"),
          "rx": "5342211", "tx": "801233", "endpoint": "193.32.127.66:51820",
          "ks_active": "0" if status in ("dropped_exposed", "disconnected") else "1", "autostart": autostart,
          "dns_applied": "10.64.0.1" if status in ("connected", "stale", "nohandshake") else "", "dns_method": "bind", "wd_state": wd_state, "wd_count": wd_count}
    out = "\n".join(f"{k}={v}" for k, v in st.items()) + "\n#PROFILES\n"
    if profiles:
        for i, n in IDS:
            out += f"PROFILE\t{i}\t{n}\t193.32.127.66:51820\t10.64.0.1\n"
    for f in favs:
        out += f"FAV\t{f}\n"
    out += f"LAST={last}\n#SETTINGS\nkillswitch={ks}\nlan=1\nautoreconnect={autoreconnect}\ndns_mode={dns_mode}\ndns_custom=\nlast_profile={last}\n"
    return out

MOCK = """
window.__cmds = [];
window.__scene = null;
window.webOS = {platformBack: function(){ window.__backed = true; }, service: {request: function(svc, o){
  var c = o.parameters.command; window.__cmds.push(c);
  var out = window.__reply(c);
  setTimeout(function(){ o.onSuccess({stdoutString: out + "\\nWGTV_RC=0\\n", stderrString: ""}); }, 5);
}}};
window.__reply = function(c){
  var fm = /profiles\.sh'? fav '([^']+)'/.exec(c);
  if (fm) { var line = "FAV\\t" + fm[1] + "\\n", sc = window.__scene;
    window.__scene = sc.indexOf(line) >= 0 ? sc.replace(line, "") : sc.replace("LAST=", line + "LAST="); return "OK"; }
  if (c.indexOf('#PROFILES') !== -1) return window.__scene;
  if (c.indexOf('upload-start.sh') !== -1) return "Upload server started\\nURL: http://192.168.1.50:8088\\nCODE: a1b2c3d4";
  if (c.indexOf('check.sh') !== -1) return '{"ip":"193.32.127.66","country":"Portugal","city":"Lisbon","mullvad_exit_ip":true,"mullvad_exit_ip_hostname":"pt-lis-wg-001"}\\n#DNS\\n10.64.0.1 ';
  if (c.indexOf('diag.sh') !== -1) return "== state ==\\nstatus=connected";
  return "OK";
};
"""

def run(shots):
    results = []
    def check(name, cond):
        results.append((name, bool(cond))); print(("  ok   " if cond else "  FAIL ") + name)

    with sync_playwright() as p:
        b = p.chromium.launch()
        ctx = b.new_context(viewport={"width": 1920, "height": 1080})
        ctx.route("**/webOSTV.js", lambda r: r.fulfill(body="", content_type="application/javascript"))
        errors = []

        def open_scene(scene, lang="pt"):
            page = ctx.new_page()
            page.on("pageerror", lambda e: errors.append(str(e)))
            page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
            page.add_init_script(MOCK + f"window.__scene = {json.dumps(scene)}; try{{localStorage.setItem('wgtvLang','{lang}')}}catch(e){{}}")
            page.goto("file://" + str(APP / "index.html"))
            page.wait_for_timeout(350)
            return page

        scenes = {
            "disconnected": snapshot("disconnected"),
            "connected": snapshot("connected", "pt-lis-wg-001"),
            "dropped_blocked": snapshot("dropped_blocked", "pt-lis-wg-001"),
            "dropped_exposed": snapshot("dropped_exposed", "pt-lis-wg-001", ks="0"),
            "nohandshake": snapshot("nohandshake", "de-fra-wg-003"),
            "empty": snapshot("disconnected", profiles=False, last=""),
            "setup": "#MISSING",
        }
        print("== states ==")
        expect = {"disconnected": ("Sem VPN", "disconnected", "net"), "connected": ("Ligado", "connected", "server"),
                  "dropped_blocked": ("Ligação perdida", "dropped_blocked", "net"), "dropped_exposed": ("Ligação perdida", "dropped_exposed", "net"),
                  "nohandshake": ("Servidor sem resposta", "nohandshake", "server"), "setup": ("Falta preparar a app", "setup", "net")}
        for name, scene in scenes.items():
            page = open_scene(scene)
            if name in expect:
                h, st, far = expect[name]
                check(f"{name}: headline '{h}'", page.inner_text("#headline") == h)
                check(f"{name}: hero data-state/far", page.get_attribute("#hero", "data-state") == st and page.get_attribute("#hero", "data-far") == far)
            if shots:
                page.screenshot(path=str(SHOTS / f"{name}.png"))
            page.close()

        print("== behaviour ==")
        page = open_scene(scenes["connected"])
        check("grid shows 12 servers", page.locator(".card").count() == 12)
        check("cities are named (Lisboa, Frankfurt, Nova Iorque)", all(x in page.inner_text("#grid") for x in ["Lisboa", "Frankfurt", "Nova Iorque", "Casa do Zé"]))
        check("active card marked", page.locator(".card.active").count() == 1)
        check("active card is blue (not amber) while connected", page.locator(".card.active.warn").count() == 0 and "Ligado" in page.locator(".card.active .tag").inner_text())
        check("facts show dns, kill switch, traffic", all(x in page.inner_text("#facts") for x in ["10.64.0.1", "ativo", "5.1 MB"]))

        page.locator('.card[data-id="de-fra-wg-003"]').focus()
        page.keyboard.press("Enter")
        page.wait_for_timeout(100)
        cmds = page.evaluate("window.__cmds")
        check("OK on a card sends connect.sh with that id", any(re.search(r"connect\.sh' ?'de-fra-wg-003'|connect\.sh 'de-fra-wg-003'", c) for c in cmds))
        page.wait_for_timeout(400)
        # focus must survive the re-render triggered by refresh()
        check("focus stays on the same card after refresh", page.evaluate("document.activeElement.getAttribute('data-id')") == "de-fra-wg-003")

        page.keyboard.press("ArrowRight"); page.keyboard.press("ArrowDown")
        check("arrow keys move focus between cards", page.evaluate("document.activeElement.classList.contains('card')") and page.evaluate("document.activeElement.getAttribute('data-id')") != "de-fra-wg-003")

        page.locator('.card[data-id="casa"]').focus()
        page.keyboard.press("F2") if False else page.evaluate("document.dispatchEvent(new KeyboardEvent('keydown',{keyCode:403,bubbles:true}))")
        page.wait_for_timeout(100)
        check("red key opens the remove confirmation", not page.locator("#confirmModal").get_attribute("hidden") and "Casa do Zé" in page.inner_text("#confirmTitle"))
        page.evaluate("document.dispatchEvent(new KeyboardEvent('keydown',{keyCode:461,bubbles:true}))")
        check("Back closes the dialog without leaving the app", page.locator("#confirmModal").get_attribute("hidden") is not None and not page.evaluate("!!window.__backed"))
        page.evaluate("document.dispatchEvent(new KeyboardEvent('keydown',{keyCode:461,bubbles:true}))")
        check("Back with nothing open exits the app", page.evaluate("!!window.__backed"))

        print("== flags ==")
        cards = page.evaluate("[...document.querySelectorAll('#grid .card')].map(c=>({t:c.innerText,src:(c.querySelector('.flag img')||{}).src||'',w:(c.querySelector('.flag img')||{}).naturalWidth||0}))")
        lis = [c for c in cards if "Lisboa" in c["t"]][0]
        casa = [c for c in cards if "Casa do Zé" in c["t"]][0]
        check("Lisboa card shows pt flag, loaded", lis["src"].endswith("flags/pt.svg") and lis["w"] > 0)
        check("all country cards have a loaded flag", all(c["w"] > 0 for c in cards if c is not casa))
        check("custom profile 'Casa do Zé' has no flag", casa["src"] == "")

        print("== settings ==")
        page.click("#btnSettings")
        page.wait_for_timeout(100)
        check("settings open, kill switch shown as on", page.get_attribute("#rowKs", "aria-checked") == "true")
        if shots: page.screenshot(path=str(SHOTS / "settings.png"))
        def geo():
            return page.evaluate("""(()=>{const d=document.querySelector('.drawer'),h=d.querySelector('h2').getBoundingClientRect(),
              b=d.querySelector('.rows'),br=b.getBoundingClientRect(),it=[...b.querySelectorAll('[data-f]')],
              f=it[0].getBoundingClientRect(),l=it[it.length-1].getBoundingClientRect();
              return {h:[h.top,h.bottom],box:[br.top,br.bottom],first:[f.top,f.bottom],last:[l.top,l.bottom],vh:innerHeight}})()""")
        page.focus("#rowKs")
        for _ in range(12): page.keyboard.press("ArrowDown"); page.wait_for_timeout(30)
        g = geo()
        check("scrolled to bottom: last row fully visible, not clipped", g["last"][1] <= g["box"][1] + 1 and g["last"][1] <= g["vh"])
        check("scrolled to bottom: title still visible", g["h"][0] >= 0)
        for _ in range(12): page.keyboard.press("ArrowUp"); page.wait_for_timeout(30)
        g = geo()
        check("back at top: Kill switch row fully inside list", g["first"][0] >= g["box"][0] and g["first"][1] <= g["box"][1])
        check("back at top: Definições title fully visible", g["h"][0] >= 0 and g["h"][1] <= g["box"][0])
        if shots: page.screenshot(path=str(SHOTS / "settings-top-again.png"))
        page.click("#rowKs"); page.wait_for_timeout(150)
        check("toggling kill switch calls settings.sh set killswitch 0", any("settings.sh' set killswitch '0'" in c or "settings.sh set killswitch '0'" in c for c in page.evaluate("window.__cmds")))
        page.click("#rowDns"); page.wait_for_timeout(100)
        check("DNS list offers 6 choices", page.locator("#dnsRows .row").count() == 6)
        if shots: page.screenshot(path=str(SHOTS / "dns.png"))
        page.click('[data-dns="ads_trackers_malware"]'); page.wait_for_timeout(150)
        check("choosing a DNS preset sends it to the TV", any("set dns_mode 'ads_trackers_malware'" in c for c in page.evaluate("window.__cmds")))
        page.close()

        print("== test + import ==")
        page = open_scene(scenes["connected"])
        page.click("#btnSecondary"); page.wait_for_timeout(200)
        txt = page.inner_text("#infoBody")
        check("test result shows IP, place and Mullvad exit", "193.32.127.66" in txt and "Lisbon" in txt and "sim" in txt)
        if shots: page.screenshot(path=str(SHOTS / "test-result.png"))
        page.click("#btnInfoClose")
        page.click("#btnImport"); page.wait_for_timeout(250)
        check("import shows address and code", page.inner_text("#importUrl") == "192.168.1.50:8088" and page.inner_text("#importCode") == "a1b2c3d4")
        if shots: page.screenshot(path=str(SHOTS / "import.png"))
        page.click("#btnImportDone"); page.wait_for_timeout(100)
        check("finishing stops the upload server", any("upload-stop.sh" in c for c in page.evaluate("window.__cmds")))
        page.close()

        print("== status chip + leak check ==")
        def chip(page): return page.inner_text("#chipText"), page.get_attribute("#chip", "data-tone")
        for name, want in [("connected", ("Protegido", "ok")), ("dropped_blocked", ("Bloqueado", "warn")),
                           ("dropped_exposed", ("Exposto", "bad")), ("disconnected", ("Sem VPN", "idle"))]:
            page = open_scene(scenes[name])
            check(f"chip in {name}: {want[0]}", chip(page) == want)
            page.close()
        page = open_scene(scenes["setup"]); check("chip hidden before setup", page.locator("#chip").get_attribute("hidden") is not None); page.close()

        page = open_scene(scenes["connected"])
        check("leak check ran by itself on start", any("check.sh" in c for c in page.evaluate("window.__cmds")))
        check("verified IP shown with a tick", "193.32.127.66 ✓" in page.inner_text("#facts"))
        page.evaluate("document.getElementById('grid').scrollTop = 600")
        check("chip stays visible after scrolling the grid", page.locator("#chip").is_visible() and page.evaluate("document.getElementById('chip').getBoundingClientRect().top") >= 0)
        page.close()

        def leak_page(reply_js, scene=None, lang="pt"):
            pg = ctx.new_page()
            pg.on("pageerror", lambda e: errors.append(str(e)))
            pg.add_init_script(MOCK + f"window.__scene = {json.dumps(scene or scenes['connected'])}; localStorage.setItem('wgtvLang','{lang}');" + reply_js)
            pg.goto("file://" + str(APP / "index.html")); pg.wait_for_timeout(450); return pg
        page = leak_page("var _r = window.__reply; window.__reply = function(c){ if (c.indexOf('check.sh')!==-1) return '{\"ip\":\"85.1.2.3\",\"country\":\"Portugal\",\"mullvad_exit_ip\":false}\\n#DNS\\n10.64.0.1 '; return _r(c); };")
        check("not exiting through Mullvad: red chip 'Possível fuga'", chip(page) == ("Possível fuga", "bad"))
        check("leak explained on the main screen", "não sai pela Mullvad" in page.inner_text("#subline"))
        if shots: page.screenshot(path=str(SHOTS / "leak.png"))
        page.close()
        page = leak_page("var _r = window.__reply; window.__reply = function(c){ if (c.indexOf('check.sh')!==-1) return '{\"ip\":\"193.32.127.66\",\"mullvad_exit_ip\":true}\\n#DNS\\n192.168.1.1 '; return _r(c); };")
        check("system DNS outside the tunnel: red chip", chip(page)[1] == "bad" and "DNS" in page.inner_text("#subline"))
        page.close()
        page = leak_page("var _r = window.__reply; window.__reply = function(c){ if (c.indexOf('check.sh')!==-1) return 'curl: not found'; return _r(c); };")
        page.wait_for_timeout(9000)
        check("check unavailable: neutral 'Ligado', not a false alarm", chip(page) == ("Ligado", "info"))
        page.close()

        print("== auto reconnect ==")
        page = open_scene(snapshot("dropped_blocked", "pt-lis-wg-001", wd_state="retrying"))
        check("retrying: chip 'A religar…' + explanation", chip(page)[0] == "A religar…" and "automaticamente" in page.inner_text("#subline"))
        if shots: page.screenshot(path=str(SHOTS / "retrying.png"))
        page.close()
        page = open_scene(snapshot("dropped_blocked", "pt-lis-wg-001", wd_state="retrying", autoreconnect="0"))
        check("auto reconnect off: plain 'Bloqueado'", chip(page)[0] == "Bloqueado")
        page.close()
        page = open_scene(scenes["connected"])
        page.click("#btnSettings"); page.wait_for_timeout(100)
        check("settings shows auto reconnect on", page.get_attribute("#rowRec", "aria-checked") == "true")
        page.click("#rowRec"); page.wait_for_timeout(150)
        check("toggle sends settings.sh set autoreconnect 0", any("set autoreconnect '0'" in c for c in page.evaluate("window.__cmds")))
        page.close()

        print("== disconnect confirmation ==")
        page = open_scene(scenes["connected"])
        page.click("#btnMain"); page.wait_for_timeout(100)
        check("Disconnect with kill switch asks first", page.locator("#confirmModal").get_attribute("hidden") is None and "IP real" in page.inner_text("#confirmText"))
        check("nothing was sent yet", not any("disconnect.sh" in c for c in page.evaluate("window.__cmds")))
        check("focus starts on Cancel (safe default)", page.evaluate("document.activeElement.id") == "btnConfirmNo")
        if shots: page.screenshot(path=str(SHOTS / "confirm-disconnect.png"))
        page.click("#btnConfirmNo"); page.wait_for_timeout(100)
        check("Cancel keeps the VPN on", not any("disconnect.sh" in c for c in page.evaluate("window.__cmds")))
        page.click("#btnMain"); page.click("#btnConfirmYes"); page.wait_for_timeout(150)
        check("confirming runs disconnect.sh", any("disconnect.sh" in c for c in page.evaluate("window.__cmds")))
        page.close()
        page = open_scene(scenes["dropped_exposed"])
        page.click("#btnSecondary"); page.wait_for_timeout(120)
        check("kill switch off: no question, disconnects directly", page.locator("#confirmModal").get_attribute("hidden") is not None and any("disconnect.sh" in c for c in page.evaluate("window.__cmds")))
        page.close()
        page = open_scene(snapshot("blocked", ""))
        page.click("#btnMain"); page.wait_for_timeout(100)
        check("unblocking also asks", "Desbloquear" in page.inner_text("#confirmTitle"))
        page.close()

        print("== favorites ==")
        page = open_scene(snapshot("disconnected", favs=("no-osl-wg-010", "es-mad-wg-001")))
        names = page.evaluate("[...document.querySelectorAll('#grid .card')].map(c=>c.getAttribute('data-id'))")
        check("favorites come first", set(names[:2]) == {"no-osl-wg-010", "es-mad-wg-001"})
        check("favorite cards show a filled star", page.locator(".card.fav .star").first.inner_text() == "★" and page.locator(".card.fav").count() == 2)
        check("group headings separate favorites from the rest", page.locator(".group").count() == 2 and "Favoritos" in page.inner_text("#grid"))
        page.locator('.card[data-id="de-fra-wg-003"]').focus()
        page.evaluate("document.dispatchEvent(new KeyboardEvent('keydown',{keyCode:404,bubbles:true}))"); page.wait_for_timeout(150)
        check("green key sends profiles.sh fav", any("profiles.sh' fav 'de-fra-wg-003'" in c or "profiles.sh fav 'de-fra-wg-003'" in c for c in page.evaluate("window.__cmds")))
        check("card becomes a favorite at once and keeps focus", page.locator('.card.fav[data-id="de-fra-wg-003"]').count() == 1 and page.evaluate("document.activeElement.getAttribute('data-id')") == "de-fra-wg-003")
        if shots: page.screenshot(path=str(SHOTS / "favorites.png"))
        page.close()
        page = open_scene(scenes["disconnected"])
        check("no favorites: no group headings", page.locator(".group").count() == 0)
        page.close()

        print("== diagnostics scroll ==")
        page = leak_page("var _r = window.__reply; window.__reply = function(c){ if (c.indexOf('diag.sh')!==-1) { var o=[]; for (var i=0;i<200;i++) o.push('line '+i+' of the diagnostic log'); return o.join('\\n'); } return _r(c); };")
        page.click("#btnSettings"); page.wait_for_timeout(100)
        page.click("#rowDiag"); page.wait_for_timeout(250)
        check("long log is focused so the remote can scroll it", page.evaluate("document.activeElement.id") == "infoLog")
        page.keyboard.press("ArrowDown"); page.wait_for_timeout(50)
        check("Down scrolls the log", page.evaluate("document.getElementById('infoLog').scrollTop") > 0)
        page.keyboard.press("ArrowUp"); page.wait_for_timeout(50)
        check("Up scrolls it back", page.evaluate("document.getElementById('infoLog').scrollTop") == 0)
        for _ in range(80): page.keyboard.press("ArrowDown")
        check("reached the last line", page.evaluate("(()=>{const l=document.getElementById('infoLog');return l.scrollTop+l.clientHeight>=l.scrollHeight-2})()"))
        page.keyboard.press("ArrowDown"); page.wait_for_timeout(50)
        check("Down at the end moves to Close", page.evaluate("document.activeElement.id") == "btnInfoClose")
        page.keyboard.press("ArrowUp"); page.wait_for_timeout(50)
        check("Up from Close returns to the log", page.evaluate("document.activeElement.id") == "infoLog")
        page.close()

        print("== QR code ==")
        page = open_scene(scenes["disconnected"])
        page.click("#btnImport"); page.wait_for_timeout(250)
        check("QR drawn in the import dialog", page.locator("#importQr svg").count() == 1)
        page.locator("#importQr").screenshot(path=str(SHOTS / "qr.png"))
        try:
            import cv2
            im = cv2.imread(str(SHOTS / "qr.png")); im = cv2.resize(im, None, fx=2, fy=2, interpolation=cv2.INTER_NEAREST)
            data, _, _ = cv2.QRCodeDetector().detectAndDecode(im)
            check("QR decodes to the upload link with the code", data == "http://192.168.1.50:8088/?c=a1b2c3d4")
        except ImportError:
            print("  skip QR decode (no opencv)")
        page.close()

        print("== english ==")
        page = open_scene(scenes["connected"], "en")
        check("English headline", page.inner_text("#headline") == "Connected")
        page.close()

        check("no JavaScript errors", not errors)
        if errors: print("   ", errors[:3])
        b.close()
    bad = [n for n, ok in results if not ok]
    print(f"\npassed: {len(results)-len(bad)}   failed: {len(bad)}")
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(run("--shots" in sys.argv))
