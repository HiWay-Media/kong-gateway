# HiWay Media Kong Gateway — l'immagine che prima non aveva una ricetta.
#
# L'immagine in produzione fino al 2026-09 (/kong:2.0.3-ubuntu-oidc-jwt) non è
# mai stata costruita da un Dockerfile: `docker history` mostra due layer `docker commit` sopra il
# kong:2.0.3-ubuntu ufficiale. Non era ricostruibile, e il suo base layer scaricava Kong da bintray,
# spento nel 2021. Questo file esiste per chiudere quel buco.
#
# KONG_VERSION è un ARG perché le versioni dei plugin cambiano con la major di Kong: 3.0 ha rimosso
# BasePlugin e impone PRIORITY/VERSION espliciti. La matrice in .github/workflows/image.yml builda
# entrambe le linee dallo stesso albero — è così che si vede cosa si rompe su 3.x senza toccare la prod.

ARG KONG_VERSION=2.8.5
FROM kong:${KONG_VERSION}-ubuntu

ARG KONG_VERSION
USER root

# Versioni pinnate, mai "latest": un plugin che si sposta sotto i piedi è come il tag mutabile che
# ha causato l'incident s3-proxy. La riga per ogni plugin dice da dove viene e perché quella versione.
#
#   kong-path-allow   seifchen, Apache 2.0, pubblico su LuaRocks.
#                     0.1-3 è la linea per Kong < 3.0, 0.2-0 quella per Kong >= 3.0 (scelta a runtime).
#   kong-oidc         nokia/kong-oidc 1.1.0 — NON compatibile 3.x e fermo dal 2022 (usa BasePlugin).
#                     Sopra la 3.0 va sostituito con un fork: vedi README, è la decisione aperta.
#   jwt-keycloak      gbbirkisson 1.1.0 — repo archiviato. Su 3.x: fork Platformatory.
#   lua-resty-openidc 1.7.2 — dipendenza di kong-oidc, pinnata esplicitamente perché la sua
#                     risoluzione automatica è la causa più comune di build non riproducibili.

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends git unzip; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    KONG_MAJOR="${KONG_VERSION%%.*}"; \
    if [ "$KONG_MAJOR" -ge 3 ]; then \
        luarocks install kong-path-allow 0.2-0; \
    else \
        luarocks install lua-resty-openidc 1.7.2-1; \
        luarocks install kong-oidc 1.1.0-0; \
        luarocks install kong-plugin-jwt-keycloak 1.1.0-1; \
        luarocks install kong-path-allow 0.1-3; \
    fi

# ⚠️ Il ramo >= 3 installa deliberatamente solo kong-path-allow: oidc e jwt-keycloak non hanno ancora
# un sostituto scelto. Una build 3.x FALLISCE lo smoke test finché quella decisione non è presa —
# è voluto: meglio una build rossa che un'immagine che si dice pronta e non lo è.

USER kong
