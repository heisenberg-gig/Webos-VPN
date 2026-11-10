package main

const pageHTML = `<!doctype html>
<html lang="pt">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>WebOS VPN</title>
<style>
:root{color-scheme:dark;--bg:#05070a;--card:#0e141b;--line:#1f2b38;--text:#eef3f8;--muted:#8fa1b5;--ok:#3ddc97;--bad:#ff6b6b;--accent:#3ddc97}
*{box-sizing:border-box}
body{margin:0;min-height:100vh;background:radial-gradient(circle at 15% 0,rgba(61,220,151,.12),transparent 30rem),var(--bg);color:var(--text);font:16px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,Arial,sans-serif;display:flex;justify-content:center;padding:28px 16px}
main{width:100%;max-width:720px}
.top{display:flex;justify-content:space-between;align-items:center;margin-bottom:18px}
.brand{font-weight:700;letter-spacing:.02em;display:flex;gap:10px;align-items:center}
.dot{width:12px;height:12px;border-radius:50%;background:var(--accent);box-shadow:0 0 14px var(--accent)}
.lang button{background:none;border:1px solid var(--line);color:var(--muted);border-radius:99px;padding:6px 12px;cursor:pointer;font:inherit;font-size:14px}
.lang button.on{color:var(--text);border-color:var(--accent)}
.card{background:var(--card);border:1px solid var(--line);border-radius:22px;padding:28px}
h1{margin:0 0 6px;font-size:28px}
p.sub{margin:0 0 22px;color:var(--muted)}
label{display:block;font-weight:600;margin:0 0 8px}
input[type=text]{width:100%;padding:14px 16px;border-radius:14px;border:1px solid var(--line);background:#070b10;color:var(--text);font:inherit;font-size:20px;letter-spacing:.2em;text-transform:lowercase}
input:focus,button:focus-visible{outline:3px solid rgba(61,220,151,.45);outline-offset:2px}
.drop{margin-top:20px;border:2px dashed var(--line);border-radius:18px;padding:34px 16px;text-align:center;color:var(--muted);cursor:pointer;transition:.15s}
.drop.over{border-color:var(--accent);background:rgba(61,220,151,.07);color:var(--text)}
.drop b{color:var(--text)}
.files{margin:14px 0 0;padding:0;list-style:none;color:var(--muted);font-size:14px}
.files li{padding:4px 0}
.btn{margin-top:20px;width:100%;border:0;border-radius:14px;padding:16px;background:var(--accent);color:#04120b;font:inherit;font-weight:700;font-size:18px;cursor:pointer}
.btn[disabled]{opacity:.45;cursor:not-allowed}
.btn.ghost{background:none;border:1px solid var(--line);color:var(--text);margin-top:10px;font-weight:600}
.res{margin:20px 0 0;padding:0;list-style:none}
.res li{display:flex;gap:10px;padding:10px 12px;border-radius:12px;background:#0a1016;margin-bottom:6px;font-size:15px;word-break:break-all}
.res .ok{color:var(--ok)}.res .err{color:var(--bad)}.res small{color:var(--muted);display:block}
.note{margin-top:18px;color:var(--muted);font-size:14px}
.hide{display:none}
</style>
</head>
<body>
<main>
 <div class="top">
  <div class="brand"><span class="dot"></span>WebOS VPN</div>
  <div class="lang"><button id="l-pt" onclick="setLang('pt')">PT</button> <button id="l-en" onclick="setLang('en')">EN</button></div>
 </div>
 <div class="card">
  <h1 data-i="title"></h1>
  <p class="sub" data-i="sub"></p>
  <div id="codeBox">
   <label for="code" data-i="code"></label>
   <input id="code" type="text" maxlength="8" autocomplete="off" autocapitalize="off" spellcheck="false" inputmode="text">
  </div>
  <div id="drop" class="drop" tabindex="0">
   <div><b data-i="drop"></b></div>
   <div data-i="dropHint"></div>
  </div>
  <input id="pick" type="file" class="hide" multiple accept=".conf,.zip,text/plain,application/zip">
  <ul id="files" class="files"></ul>
  <button id="send" class="btn" disabled data-i="send"></button>
  <ul id="res" class="res"></ul>
  <button id="done" class="btn ghost hide" data-i="done"></button>
  <p class="note" data-i="note"></p>
 </div>
</main>
<script>
var T={pt:{title:"Adicionar servidores",sub:"Carregue um ou mais ficheiros .conf, ou o ZIP que a Mullvad gera, e a TV importa tudo de uma vez.",code:"Código mostrado na TV",drop:"Arraste os ficheiros para aqui ou clique",dropHint:".conf ou .zip · vários de uma vez",send:"Enviar para a TV",done:"Concluir e fechar",note:"Os ficheiros contêm chaves privadas. Esta página só existe na sua rede local durante alguns minutos e fecha sozinha.",sel:"ficheiros",badCode:"Código errado.",locked:"Demasiadas tentativas. Volte a abrir o envio na TV.",missingFile:"Escolha pelo menos um ficheiro.",badUpload:"Não foi possível processar o envio.",closed:"Concluído. Já pode voltar à TV.",net:"Sem ligação à TV."},
en:{title:"Add servers",sub:"Upload one or more .conf files, or the ZIP Mullvad generates, and the TV imports them all at once.",code:"Code shown on the TV",drop:"Drop files here or click",dropHint:".conf or .zip · several at once",send:"Send to the TV",done:"Finish and close",note:"These files contain private keys. This page only exists on your local network for a few minutes and closes by itself.",sel:"files",badCode:"Wrong code.",locked:"Too many attempts. Start the upload again on the TV.",missingFile:"Pick at least one file.",badUpload:"The upload could not be processed.",closed:"Done. You can go back to the TV.",net:"Cannot reach the TV."}};
var lang=(navigator.language||"pt").slice(0,2)==="en"?"en":"pt";
try{lang=localStorage.getItem("wgtvLang")||lang}catch(e){}
var files=[],authed=false;
function $(i){return document.getElementById(i)}
function t(k){return T[lang][k]||k}
function setLang(l){lang=l;try{localStorage.setItem("wgtvLang",l)}catch(e){}
 document.documentElement.lang=l;
 [].forEach.call(document.querySelectorAll("[data-i]"),function(n){n.textContent=t(n.getAttribute("data-i"))});
 $("l-pt").className=l==="pt"?"on":"";$("l-en").className=l==="en"?"on":"";render()}
function render(){var ul=$("files");ul.innerHTML="";
 files.forEach(function(f){var li=document.createElement("li");li.textContent=f.name;ul.appendChild(li)});
 $("send").disabled=!files.length}
function add(list){for(var i=0;i<list.length;i++)files.push(list[i]);render()}
$("drop").onclick=function(){$("pick").click()};
$("drop").onkeydown=function(e){if(e.key==="Enter"||e.key===" ")$("pick").click()};
$("pick").onchange=function(){add(this.files);this.value=""};
["dragenter","dragover"].forEach(function(n){$("drop").addEventListener(n,function(e){e.preventDefault();this.classList.add("over")})});
["dragleave","drop"].forEach(function(n){$("drop").addEventListener(n,function(e){e.preventDefault();this.classList.remove("over")})});
$("drop").addEventListener("drop",function(e){add(e.dataTransfer.files)});
function line(cls,main,sub){var li=document.createElement("li");li.className=cls;
 li.innerHTML="<span>"+(cls==="ok"?"✓":"✗")+"</span><div></div>";
 li.lastChild.textContent=main;if(sub){var s=document.createElement("small");s.textContent=sub;li.lastChild.appendChild(s)}
 $("res").appendChild(li)}
$("send").onclick=function(){
 $("res").innerHTML="";
 var fd=new FormData();fd.append("token",$("code").value.trim());
 files.forEach(function(f){fd.append("conf",f)});
 $("send").disabled=true;
 fetch("/upload",{method:"POST",body:fd,credentials:"same-origin"}).then(function(r){return r.json().then(function(j){return{s:r.status,j:j}})}).then(function(x){
  if(x.s!==200){line("err",t(x.j.error||"badUpload"));$("send").disabled=false;return}
  authed=true;$("codeBox").classList.add("hide");files=[];render();
  x.j.results.forEach(function(r){r.ok?line("ok",r.name||r.file,r.id):line("err",r.file,r.error)});
  $("done").classList.remove("hide")
 }).catch(function(){line("err",t("net"));$("send").disabled=false})};
$("done").onclick=function(){fetch("/done",{method:"POST",credentials:"same-origin"}).then(function(){$("res").innerHTML="";line("ok",t("closed"));$("done").classList.add("hide");$("send").classList.add("hide");$("drop").classList.add("hide")})};
setLang(lang);
</script>
</body>
</html>`
