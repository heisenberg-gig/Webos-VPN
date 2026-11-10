# Componentes de terceiros

| Componente | Origem | Licença |
|---|---|---|
| `wireguard-go` 0.0.20250522 (ARMv7, estático) | binário do repositório [RodriguezCF/webos-wireguard](https://github.com/RodriguezCF/webos-wireguard), compilado a partir de [wireguard-go](https://git.zx2c4.com/wireguard-go) | MIT |
| `wg` (wireguard-tools 1.0.20260223, ARMv7, estático) | idem, a partir de [wireguard-tools](https://git.zx2c4.com/wireguard-tools) | GPL-2.0 (código-fonte no link) |
| Archivo (fonte, 400/600/800) | [Fontsource](https://fontsource.org/fonts/archivo) | SIL OFL 1.1 (`app/com.heisenberg.webosvpn/fonts/OFL.txt`) |
| `webOSTV.js` 1.2.4 | LG Electronics | Apache-2.0 |
| `exec-clean.sh` | adaptado do projeto acima | MIT |

Checksums SHA-256 dos binários incluídos, para comparares com o repositório de origem:

```
008cfe74f8196893bfa84ab007d318c91828a25765833385b157b2d90423ffff  bin/wg
cbd7b91dbca4017d7defb25ebf1ff5abb63addf1495908e1c98802ef55ce5ebc  bin/wireguard-go
```

`wgtv` (ajudante de importação e página de envio) é código deste repositório, em `uploader/`.
