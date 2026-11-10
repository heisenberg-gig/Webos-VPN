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

def snapshot(status, profile="", ks="1", autostart="1", profiles=True, last="pt-lis-wg-001", dns_mode="profile"):
    st = {"status": status, "profile": profile, "profile_name": profile, "iface": "up" if status in ("connected", "nohandshake", "stale") else "down",
          "handshake_age": "12" if status == "connected" else ("-1" if status == "nohandshake" else "300"),
          "rx": "5342211", "tx": "801233", "endpoint": "193.32.127.66:51820",
          "ks_active": "0" if status in ("dropped_exposed", "disconnected") else "1", "autostart": autostart,
          "dns_applied": "10.64.0.1" if status in ("connected", "stale", "nohandshake") else "", "dns_method": "bind"}
    out = "\n".join(f"{k}={v}" for k, v in st.items()) + "\n#PROFILES\n"
    if profiles:
        for i, n in IDS:
            out += f"PROFILE\t{i}\t{n}\t193.32.127.66:51820\t10.64.0.1\n"
    out += f"LAST={last}\n#SETTINGS\nkillswitch={ks}\nlan=1\ndns_mode={dns_mode}\ndns_custom=\nlast_profile={last}\n"
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

        print("== settings ==")
        page.click("#btnSettings")
        page.wait_for_timeout(100)
        check("settings open, kill switch shown as on", page.get_attribute("#rowKs", "aria-checked") == "true")
        if shots: page.screenshot(path=str(SHOTS / "settings.png"))
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
