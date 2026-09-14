# kong-gateway
---

## Perché questo repo esiste

L'immagine in produzione fino al settembre 2026 era `/kong:2.0.3-ubuntu-oidc-jwt`.
**Non è mai stata costruita da un Dockerfile.** `docker history` mostra due layer `docker commit`
sopra il `kong:2.0.3-ubuntu` ufficiale: qualcuno è entrato in un container, ha installato i plugin a
mano e ha committato. Il registry ne conteneva **una sola tag**, senza storia.

Era quindi un'immagine che nessuno poteva ricostruire — la stessa condizione dell'incident `s3-proxy`,
dove ce ne si è accorti solo quando si è rotta. Per di più il suo layer di base scaricava Kong da
**bintray**, spento nel 2021: nemmeno l'upstream era più rifabbricabile.

Il sorgente dei plugin è stato recuperato estraendolo dall'immagine il 2026-09-14 e si trova in
[`reference/2.0.3-ubuntu-oidc-jwt/`](reference/2.0.3-ubuntu-oidc-jwt/). È la baseline: serve a
verificare che ciò che questo Dockerfile produce sia davvero ciò che girava in produzione.

## Cosa c'è dentro

| Plugin | Origine | In prod (2.0.3) | Per Kong ≥ 3.0 |
|---|---|---|---|
| `kong-path-allow` | [seifchen](https://github.com/seifchen/kong-path-allow), Apache 2.0, pubblico su LuaRocks | `0.1-3` | ✅ **`0.2-0`**, pubblicata apposta per la 3.x |
| `oidc` | [nokia/kong-oidc](https://github.com/nokia/kong-oidc) | `1.1.0-0` | ⛔ **nessuno** — usa `BasePlugin`, rimosso in 3.0. Fermo dal 2022 |
| `jwt-keycloak` | [gbbirkisson](https://github.com/gbbirkisson/kong-plugin-jwt-keycloak), repo archiviato | `1.1.0-1` | ⚠️ fork [Platformatory](https://github.com/Platformatory/kong-plugin-jwt-keycloak), da valutare |
| `lua-resty-openidc` | dipendenza di `kong-oidc` | `1.7.2-1` | dipende dal fork scelto |

## Build

```bash
docker build --build-arg KONG_VERSION=2.8.5 -t kong-hiway:2.8.5 .   # su Apple Silicon: --platform linux/amd64
./tests/run.sh kong-hiway:2.8.5 2.8.5
```

La CI builda **entrambe** le linee dallo stesso albero: `2.8.5` (la fase 1 del piano) e `3.9.3`
(l'ultima con immagine OSS prebuilt). Serve a misurare la distanza da 3.x senza toccare la produzione.

🔴 **La build 2.8.5 oggi fallisce**, e non per i test: `luarocks` nell'immagine base non riesce più a
caricare il manifest di luarocks.org. Diagnosi, prova e conseguenze in [MILESTONES.md](MILESTONES.md), M0.

## Milestone e test

Ogni fase del piano ha un test che ne contiene il criterio di uscita: `tests/milestones/M*.sh`.
Una milestone non ancora raggiunta è dichiarata `expect xfail` — il suo test fallisce **di proposito**
e il runner la segna `XFAIL`, non rosso. Quando inizia a passare, il runner va in rosso (`XPASS`)
finché non si toglie la dichiarazione e si aggiorna il documento: serve a evitare sia i rossi che
si normalizzano, sia i traguardi raggiunti che nessuno registra.

Lo stato sta in [MILESTONES.md](MILESTONES.md); le regole di lavoro, per persone e agenti, in
[AGENTS.md](AGENTS.md).

## ⛔ La decisione aperta

**La build 3.x non passa, ed è dichiarato.** Il `Dockerfile` installa su 3.x solo `kong-path-allow`:
`oidc` e `jwt-keycloak` non hanno ancora un sostituto scelto (milestone `M3`, `XFAIL`).

Meglio un traguardo dichiarato mancante che un'immagine che si dice pronta e non lo è. Quando la
decisione è presa — quale fork, o se consolidare i due plugin in uno solo — si aggiunge la riga, il
test va in `XPASS`, e resta rosso finché `MILESTONES.md` non dice quale fork è stato scelto e perché.

⚠️ Sostituire fork abbandonati con **altri** fork abbandonati, sul percorso di autenticazione, non è
un guadagno netto di sicurezza. Va deciso con gli occhi aperti, non per inerzia.

## Pubblicazione

Solo da un tag annotato `v*` (o dispatch manuale esplicito). Un push su `main` builda e testa senza
pubblicare: `latest` deve voler dire *l'ultima release*, non *l'ultimo commit*.

```
ghcr.io/hiway-media/kong-gateway:2.8.5
ghcr.io/hiway-media/kong-gateway:2.8.5-v1.0.0
```
