/* WebOS VPN - UI. ES5 on purpose: runs on every webOS browser engine. */
(function () {
  "use strict";

  var HB = "luna://org.webosbrew.hbchannel.service";
  var BASE = "/var/lib/webosbrew/webosvpn";
  var APPID = "com.heisenberg.webosvpn";
  var ID_RE = /^[a-z0-9][a-z0-9._-]*$/;

  /* ------------------------------------------------------------------ i18n */
  var TEXT = {
    pt: {
      addServers: "Adicionar servidores", settings: "Definições",
      hintConnect: "ligar", hintRedKey: "Vermelho", hintRemove: "remover servidor",
      hintBack: "Voltar", hintExit: "sair",
      servers: "Servidores",
      emptyServers: "Ainda não há servidores. Carrega um ficheiro .conf ou o ZIP da Mullvad.",
      importTitle: "Adicionar servidores",
      importLead: "Abre este endereço num telemóvel ou computador ligado à mesma rede e envia os ficheiros .conf, ou o ZIP que a Mullvad gera.",
      address: "Endereço", code: "Código", finish: "Concluir", close: "Fechar", cancel: "Cancelar", save: "Guardar",
      importWaiting: "A aguardar ficheiros…",
      importCount: "{n} servidores na TV",
      importCountOne: "1 servidor na TV",
      importFailed: "Não foi possível abrir o envio.",
      ks: "Kill switch",
      ksDesc: "Se a VPN cair ou mudares de servidor, a internet fica cortada em vez de usar o teu IP real.",
      lan: "Permitir rede local",
      lanDesc: "Com o bloqueio ativo, mantém o acesso aos aparelhos lá de casa (Plex, partilha de ecrã).",
      dns: "DNS",
      dnsNote: "Os DNS da Mullvad só funcionam em servidores Mullvad.",
      dnsProfile: "Do ficheiro .conf", dnsProfileDesc: "Usa o DNS definido pelo servidor",
      dnsMullvad: "Mullvad", dnsMullvadDesc: "10.64.0.1, sem bloqueios",
      dnsAds: "Mullvad, sem anúncios", dnsAdsDesc: "100.64.0.1",
      dnsAdsTrackers: "Mullvad, sem anúncios nem rastreadores", dnsAdsTrackersDesc: "100.64.0.3",
      dnsAll: "Mullvad, sem anúncios, rastreadores nem malware", dnsAllDesc: "100.64.0.7",
      dnsCustom: "Personalizado", dnsCustomDesc: "Os teus próprios endereços",
      dnsCustomLabel: "Endereços separados por vírgula",
      autostart: "Ligar ao iniciar a TV",
      autostartDesc: "Religa ao último servidor. Com o kill switch, a internet só abre depois de ligar.",
      autostartOn: "Ligado", autostartOff: "Desligado",
      language: "Idioma", diag: "Diagnóstico", diagDesc: "Estado, regras de firewall, rotas e registos",
      install: "Preparar ou atualizar a app", installDesc: "Reinstala os componentes. Os servidores ficam guardados.",
      uninstall: "Remover tudo", uninstallDesc: "Apaga servidores, chaves, regras e o início automático.",
      confirmUninstallTitle: "Remover tudo?",
      confirmUninstallText: "Os servidores e as chaves guardadas na TV serão apagados. Depois podes remover a app do Homebrew Channel.",
      confirmUninstallYes: "Remover tudo",
      confirmDeleteTitle: "Remover {name}?",
      confirmDeleteText: "O ficheiro deste servidor é apagado da TV.",
      confirmDeleteYes: "Remover",
      status_loading: "A carregar…",
      status_setup: "Falta preparar a app",
      status_disconnected: "Sem VPN",
      status_connecting: "A ligar…",
      status_connected: "Ligado",
      status_nohandshake: "Servidor sem resposta",
      status_stale: "Ligação sem resposta",
      status_dropped_blocked: "Ligação perdida",
      status_dropped_exposed: "Ligação perdida",
      status_blocked: "Internet bloqueada",
      sub_setup: "Instala os componentes de rede para começar.",
      sub_disconnected: "A TV usa a tua ligação normal à internet.",
      sub_disconnectedLast: "A TV usa a tua ligação normal. Último servidor: {name}.",
      sub_connecting: "A ligar a {name}.",
      sub_connected: "Todo o tráfego da TV passa por {name}.",
      sub_nohandshake_ks: "O bloqueio mantém a internet cortada. Escolhe outro servidor ou desliga.",
      sub_nohandshake: "Escolhe outro servidor ou desliga.",
      sub_stale_ks: "Se não voltar, a internet continua bloqueada. Troca de servidor ou desliga.",
      sub_stale: "Troca de servidor ou desliga.",
      sub_dropped_blocked: "A internet está bloqueada para não expor o teu IP.",
      sub_dropped_exposed: "A TV está a usar a internet sem proteção. Ativa o kill switch nas definições.",
      sub_blocked: "O kill switch está ativo sem VPN. Desbloqueia para voltar à ligação normal.",
      near: "Esta TV", net: "Internet",
      connectTo: "Ligar a {name}", connect: "Ligar", disconnect: "Desligar", cancelConnecting: "Cancelar",
      reconnect: "Voltar a ligar", unblock: "Desbloquear internet", prepare: "Preparar",
      testConn: "Testar ligação", testing: "A testar…",
      factDns: "DNS", factKs: "Kill switch", factKsOn: "ativo", factKsOff: "desligado",
      factHs: "Handshake", factAgo: "há {n} s", factServer: "Servidor", factTraffic: "Tráfego",
      testTitle: "Resultado do teste",
      testIp: "O teu IP", testPlace: "Local", testMullvad: "Saída Mullvad", testYes: "sim", testNo: "não",
      testDnsUsed: "DNS no sistema", testFail: "Não foi possível testar. A TV precisa de curl ou wget e de certificados HTTPS.",
      diagTitle: "Diagnóstico",
      running: "A executar…", working: "A trabalhar…",
      installDone: "Componentes prontos.", installFail: "Não foi possível preparar a app.",
      connectFail: "Não foi possível ligar.",
      noService: "O Homebrew Channel não está acessível. A app precisa de uma TV com root.",
      deleted: "Servidor removido.", kbd: "Teclado"
    },
    en: {
      addServers: "Add servers", settings: "Settings",
      hintConnect: "connect", hintRedKey: "Red", hintRemove: "remove server",
      hintBack: "Back", hintExit: "exit",
      servers: "Servers",
      emptyServers: "No servers yet. Upload a .conf file or the Mullvad ZIP.",
      importTitle: "Add servers",
      importLead: "Open this address on a phone or computer on the same network and upload your .conf files, or the ZIP that Mullvad generates.",
      address: "Address", code: "Code", finish: "Finish", close: "Close", cancel: "Cancel", save: "Save",
      importWaiting: "Waiting for files…",
      importCount: "{n} servers on the TV",
      importCountOne: "1 server on the TV",
      importFailed: "Could not open the upload page.",
      ks: "Kill switch",
      ksDesc: "If the VPN drops or you switch servers, the Internet is cut instead of using your real IP.",
      lan: "Allow local network",
      lanDesc: "While blocking, keep access to devices at home (Plex, screen sharing).",
      dns: "DNS",
      dnsNote: "Mullvad DNS addresses only work on Mullvad servers.",
      dnsProfile: "From the .conf file", dnsProfileDesc: "Use the DNS the server defines",
      dnsMullvad: "Mullvad", dnsMullvadDesc: "10.64.0.1, no blocking",
      dnsAds: "Mullvad, ad blocking", dnsAdsDesc: "100.64.0.1",
      dnsAdsTrackers: "Mullvad, ads and trackers blocked", dnsAdsTrackersDesc: "100.64.0.3",
      dnsAll: "Mullvad, ads, trackers and malware blocked", dnsAllDesc: "100.64.0.7",
      dnsCustom: "Custom", dnsCustomDesc: "Your own addresses",
      dnsCustomLabel: "Addresses separated by commas",
      autostart: "Connect when the TV starts",
      autostartDesc: "Reconnects to the last server. With the kill switch, the Internet only opens once connected.",
      autostartOn: "On", autostartOff: "Off",
      language: "Language", diag: "Diagnostics", diagDesc: "State, firewall rules, routes and logs",
      install: "Set up or update the app", installDesc: "Reinstalls the components. Your servers are kept.",
      uninstall: "Remove everything", uninstallDesc: "Deletes servers, keys, rules and autostart.",
      confirmUninstallTitle: "Remove everything?",
      confirmUninstallText: "The servers and keys stored on the TV will be deleted. Afterwards you can remove the app from Homebrew Channel.",
      confirmUninstallYes: "Remove everything",
      confirmDeleteTitle: "Remove {name}?",
      confirmDeleteText: "This server's file is deleted from the TV.",
      confirmDeleteYes: "Remove",
      status_loading: "Loading…",
      status_setup: "Setup needed",
      status_disconnected: "No VPN",
      status_connecting: "Connecting…",
      status_connected: "Connected",
      status_nohandshake: "Server not answering",
      status_stale: "Connection not answering",
      status_dropped_blocked: "Connection lost",
      status_dropped_exposed: "Connection lost",
      status_blocked: "Internet blocked",
      sub_setup: "Install the network components to get started.",
      sub_disconnected: "The TV uses your normal Internet connection.",
      sub_disconnectedLast: "The TV uses your normal connection. Last server: {name}.",
      sub_connecting: "Connecting to {name}.",
      sub_connected: "All TV traffic goes through {name}.",
      sub_nohandshake_ks: "The block keeps the Internet cut. Pick another server or disconnect.",
      sub_nohandshake: "Pick another server or disconnect.",
      sub_stale_ks: "If it does not recover, the Internet stays blocked. Switch server or disconnect.",
      sub_stale: "Switch server or disconnect.",
      sub_dropped_blocked: "The Internet is blocked so your IP is not exposed.",
      sub_dropped_exposed: "The TV is using the Internet unprotected. Turn on the kill switch in Settings.",
      sub_blocked: "The kill switch is on without a VPN. Unblock to return to your normal connection.",
      near: "This TV", net: "Internet",
      connectTo: "Connect to {name}", connect: "Connect", disconnect: "Disconnect", cancelConnecting: "Cancel",
      reconnect: "Reconnect", unblock: "Unblock Internet", prepare: "Set up",
      testConn: "Test connection", testing: "Testing…",
      factDns: "DNS", factKs: "Kill switch", factKsOn: "on", factKsOff: "off",
      factHs: "Handshake", factAgo: "{n} s ago", factServer: "Server", factTraffic: "Traffic",
      testTitle: "Test result",
      testIp: "Your IP", testPlace: "Location", testMullvad: "Mullvad exit", testYes: "yes", testNo: "no",
      testDnsUsed: "System DNS", testFail: "Could not test. The TV needs curl or wget and HTTPS certificates.",
      diagTitle: "Diagnostics",
      running: "Running…", working: "Working…",
      installDone: "Components ready.", installFail: "Could not set up the app.",
      connectFail: "Could not connect.",
      noService: "Homebrew Channel is not reachable. This app needs a rooted TV.",
      deleted: "Server removed.", kbd: "Keyboard"
    }
  };

  var lang = "pt";
  try {
    var saved = localStorage.getItem("wgtvLang");
    if (saved === "pt" || saved === "en") lang = saved;
    else if ((navigator.language || "").slice(0, 2) === "en") lang = "en";
  } catch (e) { /* storage may be unavailable */ }

  function t(key, vars) {
    var s = (TEXT[lang] && TEXT[lang][key]) || TEXT.pt[key] || key;
    if (vars) for (var k in vars) if (vars.hasOwnProperty(k)) s = s.replace("{" + k + "}", vars[k]);
    return s;
  }

  /* --------------------------------------------------------- place names */
  var CITIES = {
    ams: "Amesterdão", ath: "Atenas", atl: "Atlanta", bcn: "Barcelona", beg: "Belgrado", ber: "Berlim",
    bkk: "Banguecoque", bne: "Brisbane", bog: "Bogotá", bos: "Boston", bru: "Bruxelas", bts: "Bratislava",
    bud: "Budapeste", buh: "Bucareste", bue: "Buenos Aires", chi: "Chicago", cph: "Copenhaga", dal: "Dallas",
    den: "Denver", det: "Detroit", dub: "Dublin", dus: "Düsseldorf", fra: "Frankfurt", got: "Gotemburgo",
    gva: "Genebra", hel: "Helsínquia", hkg: "Hong Kong", hou: "Houston", ist: "Istambul", jnb: "Joanesburgo",
    kul: "Kuala Lumpur", lax: "Los Angeles", lis: "Lisboa", lju: "Liubliana", lon: "Londres", mad: "Madrid",
    man: "Manchester", mel: "Melbourne", mex: "Cidade do México", mia: "Miami", mil: "Milão", mma: "Malmö",
    mnl: "Manila", mtl: "Montreal", nyc: "Nova Iorque", osl: "Oslo", par: "Paris", per: "Perth",
    phx: "Phoenix", prg: "Praga", qro: "Querétaro", rig: "Riga", rix: "Riga", rom: "Roma", sao: "São Paulo",
    sea: "Seattle", sgp: "Singapura", sjc: "San José", slc: "Salt Lake City", sof: "Sófia", sto: "Estocolmo",
    syd: "Sydney", tia: "Tirana", tll: "Tallinn", tor: "Toronto", tpe: "Taipé", tyo: "Tóquio",
    uio: "Quito", van: "Vancouver", vce: "Veneza", vie: "Viena", vno: "Vilnius", waw: "Varsóvia", zag: "Zagreb",
    zrh: "Zurique"
  };

  var regionNames = null;
  function countryName(code) {
    try {
      if (typeof Intl !== "undefined" && Intl.DisplayNames) {
        if (!regionNames || regionNames.lang !== lang) {
          regionNames = { lang: lang, dn: new Intl.DisplayNames([lang], { type: "region" }) };
        }
        var n = regionNames.dn.of(code.toUpperCase());
        if (n && n !== code.toUpperCase()) return n;
      }
    } catch (e) { /* fall through */ }
    return code.toUpperCase();
  }

  // pt-lis-wg-001  /  mullvad-pt12  /  anything else
  function describe(p) {
    var m = /^([a-z]{2})-([a-z]{3})-wg-(\d+)/.exec(p.id);
    if (m) {
      return { flag: true, cc: m[1].toUpperCase(), city: CITIES[m[2]] || m[2].toUpperCase(), country: countryName(m[1]), num: m[3], sort: countryName(m[1]) + "|" + (CITIES[m[2]] || m[2]) + "|" + m[3] };
    }
    m = /^(?:mullvad-)?([a-z]{2})(\d+)$/.exec(p.id);
    if (m) {
      return { flag: true, cc: m[1].toUpperCase(), city: countryName(m[1]), country: "", num: m[2], sort: countryName(m[1]) + "||" + m[2] };
    }
    return { flag: false, cc: (p.name || p.id).slice(0, 2).toUpperCase(), city: p.name || p.id, country: "", num: "", sort: "~" + (p.name || p.id) };
  }

  function placeName(p) {
    if (!p) return "";
    var d = describe(p);
    return d.country && d.country !== d.city ? d.city + ", " + d.country : d.city;
  }

  /* ------------------------------------------------------------- helpers */
  function $(id) { return document.getElementById(id); }
  function setText(el, txt) { if (el.textContent !== txt) el.textContent = txt; }
  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }
  function scriptPath(name) { return BASE + "/scripts/" + name; }

  function bytes(n) {
    n = Number(n) || 0;
    if (n < 1024) return n + " B";
    if (n < 1048576) return (n / 1024).toFixed(1) + " KB";
    if (n < 1073741824) return (n / 1048576).toFixed(1) + " MB";
    return (n / 1073741824).toFixed(2) + " GB";
  }

  /* ------------------------------------------------------------- luna exec */
  function serviceAvailable() {
    return typeof webOS !== "undefined" && webOS.service && typeof webOS.service.request === "function";
  }

  // cb(ok, stdout, rc). rc is the shell exit code of `command` (or -1).
  function sh(command, cb, timeoutMs) {
    var done = false;
    var timer = setTimeout(function () { if (!done) { done = true; cb(false, "timeout", -1); } }, timeoutMs || 20000);
    if (!serviceAvailable()) { clearTimeout(timer); done = true; cb(false, t("noService"), -1); return; }
    var wrapped = "( " + command + " ) 2>&1; echo; echo WGTV_RC=$?; exit 0";
    try {
      webOS.service.request(HB, {
        method: "exec",
        parameters: { command: wrapped },
        onSuccess: function (res) {
          if (done) return; done = true; clearTimeout(timer);
          var out = (res.stdoutString || "") + (res.stderrString || "");
          var m = /WGTV_RC=(\d+)/.exec(out);
          out = out.replace(/\n?WGTV_RC=\d+\s*$/, "").replace(/\s+$/, "");
          cb(true, out, m ? parseInt(m[1], 10) : -1);
        },
        onFailure: function (err) {
          if (done) return; done = true; clearTimeout(timer);
          cb(false, JSON.stringify(err), -1);
        }
      });
    } catch (e) {
      if (!done) { done = true; clearTimeout(timer); cb(false, String(e.message || e), -1); }
    }
  }

  /* ----------------------------------------------------------------- state */
  var S = {
    installed: null,
    st: { status: "loading" },
    profiles: [],
    last: "",
    settings: { killswitch: "1", lan: "1", dns_mode: "profile", dns_custom: "", last_profile: "" },
    busy: null,          // "connecting" | "working" | null
    busyProfile: "",
    sig: ""
  };

  function parseKV(text) {
    var o = {};
    var lines = text.split("\n");
    for (var i = 0; i < lines.length; i++) {
      var k = lines[i].indexOf("=");
      if (k > 0) o[lines[i].slice(0, k)] = lines[i].slice(k + 1);
    }
    return o;
  }

  function parseSnapshot(out) {
    var parts = out.split("#PROFILES");
    if (parts[0].indexOf("#MISSING") !== -1) return null;
    var st = parseKV(parts[0]);
    var rest = (parts[1] || "").split("#SETTINGS");
    var profiles = [], last = "";
    var lines = rest[0].split("\n");
    for (var i = 0; i < lines.length; i++) {
      var f = lines[i].split("\t");
      if (f[0] === "PROFILE" && f[1]) profiles.push({ id: f[1], name: f[2] || f[1], endpoint: f[3] || "", dns: f[4] || "" });
      else if (lines[i].indexOf("LAST=") === 0) last = lines[i].slice(5);
    }
    profiles.sort(function (a, b) { return describe(a).sort < describe(b).sort ? -1 : 1; });
    return { st: st, profiles: profiles, last: last, settings: parseKV(rest[1] || "") };
  }

  var SNAP_CMD =
    "if [ -x " + scriptPath("state.sh") + " ]; then " +
    scriptPath("state.sh") + "; echo '#PROFILES'; " + scriptPath("profiles.sh") + " list; echo '#SETTINGS'; " + scriptPath("settings.sh") + " get; " +
    "else echo '#MISSING'; fi";

  var refreshing = false;
  function refresh(cb) {
    if (refreshing) { if (cb) cb(); return; }
    refreshing = true;
    sh(SNAP_CMD, function (ok, out) {
      refreshing = false;
      if (ok) {
        var snap = parseSnapshot(out);
        if (!snap) { S.installed = false; S.st = { status: "setup" }; }
        else {
          S.installed = true;
          S.st = snap.st; S.profiles = snap.profiles; S.last = snap.last;
          for (var k in snap.settings) if (snap.settings.hasOwnProperty(k)) S.settings[k] = snap.settings[k];
        }
      } else if (S.installed === null) {
        S.installed = false; S.st = { status: "setup" };
        showToast(out, false);
      }
      render();
      if (cb) cb();
    }, 15000);
  }

  /* ---------------------------------------------------------------- render */
  function profileById(id) {
    for (var i = 0; i < S.profiles.length; i++) if (S.profiles[i].id === id) return S.profiles[i];
    return null;
  }

  function effectiveStatus() {
    if (S.busy === "connecting") return "connecting";
    return S.st.status || "loading";
  }

  function hero() {
    var status = effectiveStatus();
    var ks = S.settings.killswitch === "1";
    var activeId = S.busy === "connecting" ? S.busyProfile : S.st.profile;
    var active = profileById(activeId);
    var name = active ? placeName(active) : (S.st.profile_name || "");
    var last = profileById(S.settings.last_profile || S.last) || S.profiles[0] || null;

    var v = { status: status, far: "net", farLabel: t("net"), main: "", mainAct: "", sec: "", secAct: "", sub: "" };
    if (status === "connected" || status === "connecting" || status === "nohandshake" || status === "stale") {
      v.far = "server"; v.farLabel = name || "VPN";
    }
    switch (status) {
      case "setup": v.sub = t("sub_setup"); v.main = t("prepare"); v.mainAct = "install"; break;
      case "loading": break;
      case "connected":
        v.sub = t("sub_connected", { name: name });
        v.main = t("disconnect"); v.mainAct = "disconnect"; v.sec = t("testConn"); v.secAct = "test"; break;
      case "connecting":
        v.sub = t("sub_connecting", { name: name });
        v.main = t("cancelConnecting"); v.mainAct = "disconnect"; break;
      case "nohandshake":
        v.sub = t(ks ? "sub_nohandshake_ks" : "sub_nohandshake");
        v.main = t("disconnect"); v.mainAct = "disconnect"; break;
      case "stale":
        v.sub = t(ks ? "sub_stale_ks" : "sub_stale");
        v.main = t("disconnect"); v.mainAct = "disconnect"; break;
      case "dropped_blocked":
        v.sub = t("sub_dropped_blocked");
        v.main = t("reconnect"); v.mainAct = "reconnect"; v.sec = t("disconnect"); v.secAct = "disconnect"; break;
      case "dropped_exposed":
        v.sub = t("sub_dropped_exposed");
        v.main = t("reconnect"); v.mainAct = "reconnect"; v.sec = t("disconnect"); v.secAct = "disconnect"; break;
      case "blocked":
        v.sub = t("sub_blocked");
        v.main = t("unblock"); v.mainAct = "disconnect"; break;
      default: // disconnected
        v.sub = last ? t("sub_disconnectedLast", { name: placeName(last) }) : t("sub_disconnected");
        if (last) { v.main = t("connectTo", { name: placeName(last) }); v.mainAct = "connect:" + last.id; }
        else { v.main = t("addServers"); v.mainAct = "import"; }
        v.sec = t("testConn"); v.secAct = "test";
    }
    return v;
  }

  function facts() {
    var st = S.st, out = [];
    var status = effectiveStatus();
    if (status === "connected" || status === "stale" || status === "nohandshake") {
      if (st.dns_applied) out.push([t("factDns"), st.dns_applied]);
      out.push([t("factKs"), st.ks_active === "1" ? t("factKsOn") : t("factKsOff")]);
      if (Number(st.handshake_age) >= 0) out.push([t("factHs"), t("factAgo", { n: st.handshake_age })]);
      if (status === "connected") out.push([t("factTraffic"), "↓ " + bytes(st.rx) + "  ↑ " + bytes(st.tx)]);
    } else if (status === "dropped_blocked" || status === "blocked") {
      out.push([t("factKs"), t("factKsOn")]);
    } else if (status === "dropped_exposed") {
      out.push([t("factKs"), t("factKsOff")]);
    }
    return out;
  }

  var lastFocusId = null;
  function render() {
    var v = hero();
    var h = $("hero");
    if (h.getAttribute("data-state") !== v.status) h.setAttribute("data-state", v.status);
    if (h.getAttribute("data-far") !== v.far) h.setAttribute("data-far", v.far);
    setText($("headline"), t("status_" + v.status));
    setText($("subline"), v.sub || " ");
    setText($("nearLabel"), t("near"));
    setText($("farLabel"), v.farLabel);

    var f = facts(), html = "";
    for (var i = 0; i < f.length; i++) html += '<li><span class="k">' + esc(f[i][0]) + "</span><span>" + esc(f[i][1]) + "</span></li>";
    if ($("facts").getAttribute("data-html") !== html) { $("facts").innerHTML = html; $("facts").setAttribute("data-html", html); }

    var main = $("btnMain");
    setText(main, v.main || " ");
    main.setAttribute("data-act", v.mainAct);
    main.setAttribute("aria-busy", S.busy === "working" ? "true" : "false");
    main.hidden = !v.main;
    var sec = $("btnSecondary");
    sec.hidden = !v.sec; setText(sec, v.sec); sec.setAttribute("data-act", v.secAct);

    renderGrid(v.status);
    renderSettings();
  }

  function renderGrid(gridStatus) {
    var status = gridStatus;
    var activeId = S.busy === "connecting" ? S.busyProfile : S.st.profile;
    var warn = status !== "connected" && status !== "connecting";
    var sig = [lang, activeId, warn ? "w" : "o"];
    for (var i = 0; i < S.profiles.length; i++) sig.push(S.profiles[i].id + S.profiles[i].name);
    sig = sig.join("|");
    var empty = S.installed && S.profiles.length === 0;
    $("empty").hidden = !empty;
    $("grid").hidden = empty;
    setText($("emptyText"), t("emptyServers"));
    setText($("serversTitle"), t("servers"));
    setText($("serversCount"), S.profiles.length ? String(S.profiles.length) : "");
    $("serversWrap").hidden = S.installed === false;
    if (sig === S.sig) return;
    S.sig = sig;

    var focused = document.activeElement && document.activeElement.getAttribute && document.activeElement.getAttribute("data-id");
    var html = "";
    for (var j = 0; j < S.profiles.length; j++) {
      var p = S.profiles[j], d = describe(p);
      var act = p.id === activeId;
      var tag = act ? (status === "connected" ? t("status_connected") : (status === "connecting" ? "…" : "")) : "";
      html += '<button class="card' + (act ? " active" : "") + (act && warn ? " warn" : "") + '" data-f data-id="' + esc(p.id) + '" role="listitem">' +
        (d.flag
          ? '<span class="flag"><img src="flags/' + d.cc.toLowerCase() + '.svg" alt="" onerror="this.parentNode.className=\'cc\';this.parentNode.textContent=\'' + d.cc + '\'"></span>'
          : '<span class="cc">' + esc(d.cc) + "</span>") +
        '<span class="city">' + esc(d.city) + "</span>" +
        '<span class="meta">' + esc((d.country ? d.country + (d.num ? " · " : "") : "") + (d.num ? d.num : (d.country ? "" : p.endpoint))) + "</span>" +
        (tag ? '<span class="tag">' + esc(tag) + "</span>" : "") + "</button>";
    }
    $("grid").innerHTML = html;
    if (focused) {
      var again = document.querySelector('.card[data-id="' + focused + '"]');
      if (again) again.focus();
    }
  }

  var DNS_MODES = [
    ["profile", "dnsProfile", "dnsProfileDesc"], ["mullvad", "dnsMullvad", "dnsMullvadDesc"],
    ["ads", "dnsAds", "dnsAdsDesc"], ["ads_trackers", "dnsAdsTrackers", "dnsAdsTrackersDesc"],
    ["ads_trackers_malware", "dnsAll", "dnsAllDesc"], ["custom", "dnsCustom", "dnsCustomDesc"]
  ];
  function dnsLabel(mode) {
    for (var i = 0; i < DNS_MODES.length; i++) if (DNS_MODES[i][0] === mode) {
      var s = t(DNS_MODES[i][1]);
      if (mode === "custom" && S.settings.dns_custom) s += ": " + S.settings.dns_custom.replace(/,/g, ", ");
      return s;
    }
    return mode;
  }

  function renderSettings() {
    var i18n = document.querySelectorAll("[data-i18n]");
    for (var i = 0; i < i18n.length; i++) setText(i18n[i], t(i18n[i].getAttribute("data-i18n")));
    $("rowKs").setAttribute("aria-checked", S.settings.killswitch === "1" ? "true" : "false");
    $("rowLan").setAttribute("aria-checked", S.settings.lan === "1" ? "true" : "false");
    $("rowAuto").setAttribute("aria-checked", S.st.autostart === "1" ? "true" : "false");
    setText($("dnsValue"), dnsLabel(S.settings.dns_mode));
    setText($("langValue"), lang === "pt" ? "Português" : "English");
    document.documentElement.lang = lang;
  }

  /* ----------------------------------------------------------------- toast */
  var toastTimer = null;
  function showToast(msg, good) {
    var el = $("toast");
    el.textContent = msg; el.className = "toast" + (good ? " good" : ""); el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.hidden = true; }, 9000);
  }
  function errorLines(out) {
    var m = out.match(/^(ERROR|WARNING).*$/gm);
    return m ? m.slice(0, 3).join("\n") : "";
  }

  /* ---------------------------------------------------------------- actions */
  function connect(id) {
    if (S.busy || !ID_RE.test(id)) return;
    S.busy = "connecting"; S.busyProfile = id; render();
    sh(scriptPath("connect.sh") + " '" + id + "'", function (ok, out, rc) {
      S.busy = null; S.busyProfile = "";
      if (!ok || (rc !== 0 && rc !== 3)) showToast(errorLines(out) || t("connectFail"), false);
      else if (rc === 3) showToast(errorLines(out) || t("status_nohandshake"), false);
      refresh();
    }, 90000);
  }

  function disconnect() {
    if (S.busy === "working") return;
    S.busy = "working"; render();
    sh(scriptPath("disconnect.sh"), function (ok, out, rc) {
      S.busy = null;
      if (!ok || rc !== 0) showToast(errorLines(out) || out, false);
      refresh();
    }, 45000);
  }

  function install() {
    if (S.busy) return;
    S.busy = "working"; render();
    sh("sh /media/developer/apps/usr/palm/applications/" + APPID + "/payload/webosvpn/install.sh || " +
       "sh $(find /media -path '*/applications/" + APPID + "/payload/webosvpn/install.sh' 2>/dev/null | head -1)", function (ok, out, rc) {
      S.busy = null;
      showToast(rc === 0 ? t("installDone") : (errorLines(out) || t("installFail")), rc === 0);
      S.installed = null; refresh();
    }, 90000);
  }

  function testConnection() {
    showInfo(t("testTitle"), "<p class='lead'>" + esc(t("testing")) + "</p>");
    sh(scriptPath("check.sh") + "; echo; echo '#DNS'; grep '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\\n' ' '", function (ok, out) {
      var parts = out.split("#DNS");
      var dns = (parts[1] || "").replace(/^\s+|\s+$/g, "");
      var j = null;
      try { j = JSON.parse(parts[0]); } catch (e) { /* not JSON */ }
      if (!j) { showInfo(t("testTitle"), "<p class='lead bad'>" + esc(t("testFail")) + "</p>", parts[0]); return; }
      var rows = "<div class='result-grid'>" +
        "<span class='k'>" + esc(t("testIp")) + "</span><b>" + esc(j.ip || "?") + "</b>" +
        "<span class='k'>" + esc(t("testPlace")) + "</span><span>" + esc([j.city, j.country].filter(Boolean).join(", ")) + "</span>" +
        "<span class='k'>" + esc(t("testMullvad")) + "</span><span class='" + (j.mullvad_exit_ip ? "ok" : "bad") + "'>" +
        esc(j.mullvad_exit_ip ? t("testYes") + (j.mullvad_exit_ip_hostname ? " (" + j.mullvad_exit_ip_hostname + ")" : "") : t("testNo")) + "</span>" +
        "<span class='k'>" + esc(t("testDnsUsed")) + "</span><span>" + esc(dns || "?") + "</span></div>";
      showInfo(t("testTitle"), rows);
    }, 25000);
  }

  function setSetting(key, val, cb) {
    S.settings[key] = val; render();
    sh(scriptPath("settings.sh") + " set " + key + " '" + String(val).replace(/'/g, "") + "'", function (ok, out, rc) {
      if (!ok || rc !== 0) showToast(errorLines(out) || out, false);
      refresh(cb);
    }, 30000);
  }

  function toggleAutostart() {
    var on = S.st.autostart === "1";
    S.st.autostart = on ? "0" : "1"; render();
    sh(scriptPath("autostart.sh") + " " + (on ? "disable" : "enable"), function () { refresh(); }, 15000);
  }

  function showDiag() {
    showInfo(t("diagTitle"), "<p class='lead'>" + esc(t("running")) + "</p>");
    sh(scriptPath("diag.sh"), function (ok, out) { showInfo(t("diagTitle"), "", out); }, 30000);
  }

  function deleteProfile(id) {
    var p = profileById(id); if (!p) return;
    confirmDialog(t("confirmDeleteTitle", { name: placeName(p) }), t("confirmDeleteText"), t("confirmDeleteYes"), function () {
      sh(scriptPath("profiles.sh") + " delete '" + id + "'", function (ok, out, rc) {
        showToast(rc === 0 ? t("deleted") : (errorLines(out) || out), rc === 0);
        S.sig = ""; refresh();
      }, 15000);
    });
  }

  function uninstallAll() {
    confirmDialog(t("confirmUninstallTitle"), t("confirmUninstallText"), t("confirmUninstallYes"), function () {
      S.busy = "working"; render();
      sh(scriptPath("uninstall.sh"), function (ok, out) {
        S.busy = null; S.installed = false; S.st = { status: "setup" }; S.profiles = []; S.sig = "";
        closeAllModals(); showToast(out.split("\n").pop(), true); render();
      }, 60000);
    });
  }

  /* ---------------------------------------------------------------- modals */
  var modalStack = [];
  var returnFocus = [];

  function openModal(id, focusId) {
    var m = $(id);
    returnFocus.push(document.activeElement);
    m.hidden = false; modalStack.push(id);
    var target = focusId ? $(focusId) : m.querySelector("[data-f]");
    if (target) target.focus();
  }
  function closeModal(id) {
    var m = $(id); if (!m || m.hidden) return;
    m.hidden = true;
    var i = modalStack.lastIndexOf(id); if (i >= 0) modalStack.splice(i, 1);
    var back = returnFocus.pop();
    if (back && back.focus && document.body.contains(back)) back.focus();
  }
  function closeAllModals() { while (modalStack.length) closeModal(modalStack[modalStack.length - 1]); }
  function topModal() { return modalStack.length ? modalStack[modalStack.length - 1] : null; }

  function showInfo(title, html, log) {
    setText($("infoTitle"), title);
    $("infoBody").innerHTML = html || "";
    var pre = $("infoLog");
    if (log) { pre.textContent = log; pre.hidden = false; } else { pre.hidden = true; }
    if ($("infoModal").hidden) openModal("infoModal", "btnInfoClose");
  }

  var confirmYes = null;
  function confirmDialog(title, text, yesLabel, onYes) {
    setText($("confirmTitle"), title); setText($("confirmText"), text); setText($("btnConfirmYes"), yesLabel);
    confirmYes = onYes; openModal("confirmModal", "btnConfirmNo");
  }

  /* upload (import) */
  var importTimer = null;
  function openImport() {
    if (S.installed === false) { install(); return; }
    setText($("importUrl"), "…"); setText($("importCode"), "…"); setText($("importStatus"), t("importWaiting"));
    openModal("importModal", "btnImportDone");
    sh(scriptPath("upload-start.sh"), function (ok, out, rc) {
      var u = /URL:\s*(\S+)/.exec(out), c = /CODE:\s*(\S+)/.exec(out);
      if (!u || !c) { setText($("importStatus"), t("importFailed") + " " + errorLines(out)); return; }
      setText($("importUrl"), u[1].replace(/^http:\/\//, "")); setText($("importCode"), c[1]);
      clearInterval(importTimer);
      importTimer = setInterval(function () { refresh(function () {
        var n = S.profiles.length;
        setText($("importStatus"), n === 1 ? t("importCountOne") : t("importCount", { n: n }));
      }); }, 3000);
    }, 20000);
  }
  function closeImport() {
    clearInterval(importTimer); importTimer = null;
    sh(scriptPath("upload-stop.sh"), function () {}, 10000);
    closeModal("importModal"); refresh();
  }

  /* dns picker */
  function openDns() {
    var html = "";
    for (var i = 0; i < DNS_MODES.length; i++) {
      var m = DNS_MODES[i];
      html += '<button class="row' + (S.settings.dns_mode === m[0] ? " selected" : "") + '" data-f data-dns="' + m[0] + '">' +
        '<span class="row-text"><span class="row-title">' + esc(t(m[1])) + '</span><span class="row-desc">' + esc(t(m[2])) + "</span></span>" +
        (S.settings.dns_mode === m[0] ? '<span class="chev ok">✓</span>' : "") + "</button>";
    }
    $("dnsRows").innerHTML = html;
    $("dnsCustomBox").hidden = S.settings.dns_mode !== "custom";
    $("dnsCustomInput").value = (S.settings.dns_custom || "").replace(/,/g, ", ");
    openModal("dnsModal", null);
    var sel = document.querySelector("#dnsRows .selected");
    if (sel) sel.focus();
  }

  /* ----------------------------------------------------------------- input */
  function act(a) {
    if (!a) return;
    if (a === "install") install();
    else if (a === "disconnect") disconnect();
    else if (a === "reconnect") connect(S.st.profile || S.settings.last_profile);
    else if (a === "test") testConnection();
    else if (a === "import") openImport();
    else if (a.indexOf("connect:") === 0) connect(a.slice(8));
  }

  document.addEventListener("click", function (e) {
    var el = e.target;
    while (el && el !== document.body && !(el.getAttribute && (el.hasAttribute("data-f")))) el = el.parentNode;
    if (!el || el === document.body) return;
    var id = el.id;
    if (el.classList.contains("card")) {
      var pid = el.getAttribute("data-id");
      if (pid === S.st.profile && effectiveStatus() === "connected") return;
      connect(pid); return;
    }
    if (el.hasAttribute("data-dns")) {
      var mode = el.getAttribute("data-dns");
      if (mode === "custom") { S.settings.dns_mode = "custom"; $("dnsCustomBox").hidden = false; $("dnsCustomInput").focus(); return; }
      closeModal("dnsModal"); setSetting("dns_mode", mode); return;
    }
    switch (id) {
      case "btnMain": act(el.getAttribute("data-act")); break;
      case "btnSecondary": act(el.getAttribute("data-act")); break;
      case "btnImport": case "btnEmptyAdd": openImport(); break;
      case "btnSettings": renderSettings(); openModal("settingsModal", "rowKs"); break;
      case "btnImportDone": closeImport(); break;
      case "btnInfoClose": closeModal("infoModal"); break;
      case "btnConfirmNo": closeModal("confirmModal"); break;
      case "btnConfirmYes": closeModal("confirmModal"); if (confirmYes) { var f = confirmYes; confirmYes = null; f(); } break;
      case "rowKs": setSetting("killswitch", S.settings.killswitch === "1" ? "0" : "1"); break;
      case "rowLan": setSetting("lan", S.settings.lan === "1" ? "0" : "1"); break;
      case "rowAuto": toggleAutostart(); break;
      case "rowDns": openDns(); break;
      case "rowLang":
        lang = lang === "pt" ? "en" : "pt"; try { localStorage.setItem("wgtvLang", lang); } catch (x) { /* ignore */ }
        S.sig = ""; render(); break;
      case "rowDiag": showDiag(); break;
      case "rowInstall": closeModal("settingsModal"); install(); break;
      case "rowUninstall": uninstallAll(); break;
      case "btnDnsCustomSave":
        var val = $("dnsCustomInput").value.replace(/\s+/g, "");
        if (!/^(\d{1,3}\.){3}\d{1,3}(,(\d{1,3}\.){3}\d{1,3})*$/.test(val)) { showToast("1.1.1.1, 9.9.9.9", false); return; }
        closeModal("dnsModal");
        setSetting("dns_custom", val, function () { setSetting("dns_mode", "custom"); });
        break;
    }
  });

  function keyCode(e) {
    if (typeof e.keyCode === "number" && e.keyCode) return e.keyCode;
    var map = { ArrowLeft: 37, ArrowUp: 38, ArrowRight: 39, ArrowDown: 40, Enter: 13, Escape: 27, GoBack: 461 };
    return map[e.key] || 0;
  }

  function focusables() {
    var top = topModal();
    var root = top ? $(top) : document.getElementById("app");
    var all = root.querySelectorAll("[data-f]");
    var out = [];
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      if (el.disabled || el.hidden || el.offsetWidth === 0 || el.offsetHeight === 0) continue;
      out.push(el);
    }
    return out;
  }

  function move(dir) {
    var els = focusables();
    if (!els.length) return;
    var cur = document.activeElement;
    if (els.indexOf(cur) === -1) { els[0].focus(); return; }
    var cr = cur.getBoundingClientRect(), cx = cr.left + cr.width / 2, cy = cr.top + cr.height / 2;
    var best = null, bestScore = Infinity;
    for (var i = 0; i < els.length; i++) {
      var c = els[i]; if (c === cur) continue;
      var r = c.getBoundingClientRect(), dx = r.left + r.width / 2 - cx, dy = r.top + r.height / 2 - cy;
      var horizontal = dir === "left" || dir === "right";
      var primary = horizontal ? dx : dy, cross = horizontal ? dy : dx;
      if ((dir === "left" && primary >= -2) || (dir === "right" && primary <= 2) ||
          (dir === "up" && primary >= -2) || (dir === "down" && primary <= 2)) continue;
      var score = Math.abs(primary) + Math.abs(cross) * 2;
      if (score < bestScore) { best = c; bestScore = score; }
    }
    if (!best) return;
    best.focus();
    ensureVisible(best);
  }

  // scrollIntoView would also scroll ancestors (and cut off titles); scroll only
  // the list that contains the item, and snap to the very top/bottom at the ends.
  function ensureVisible(el) {
    var box = el.parentNode;
    while (box && box !== document.body && !(box.classList && (box.classList.contains("grid") || box.classList.contains("rows")))) box = box.parentNode;
    if (!box || box === document.body) return;
    var br = box.getBoundingClientRect(), r = el.getBoundingClientRect(), pad = 28;
    if (r.top < br.top + pad) box.scrollTop -= (br.top + pad - r.top);
    else if (r.bottom > br.bottom - pad) box.scrollTop += (r.bottom - (br.bottom - pad));
    var items = box.querySelectorAll("[data-f]");
    if (items.length && items[0] === el) box.scrollTop = 0;
    else if (items.length && items[items.length - 1] === el) box.scrollTop = box.scrollHeight;
  }

  document.addEventListener("keydown", function (e) {
    var code = keyCode(e);
    var a = document.activeElement;
    var typing = a && a.tagName === "INPUT";

    if (code === 461 || code === 27) {
      var top = topModal();
      if (top) {
        e.preventDefault();
        if (top === "importModal") closeImport(); else closeModal(top);
      } else if (code === 461 && typeof webOS !== "undefined" && webOS.platformBack) {
        e.preventDefault(); webOS.platformBack();
      }
      return;
    }
    if (code === 403 && !topModal() && a && a.classList && a.classList.contains("card")) { // red key
      e.preventDefault(); deleteProfile(a.getAttribute("data-id")); return;
    }
    if (typing && (code === 37 || code === 39)) return;
    if (code === 37) { e.preventDefault(); move("left"); }
    else if (code === 38) { e.preventDefault(); move("up"); }
    else if (code === 39) { e.preventDefault(); move("right"); }
    else if (code === 40) { e.preventDefault(); move("down"); }
    else if (code === 13 && a && a.tagName === "BUTTON") { e.preventDefault(); a.click(); }
  });

  /* ------------------------------------------------------------------ boot */
  function boot() {
    render();
    refresh(function () {
      var first = $("btnMain");
      if (first && !first.hidden) first.focus();
    });
    setInterval(function () { if (!S.busy && !topModal()) refresh(); }, 5000);
  }
  boot();
})();
