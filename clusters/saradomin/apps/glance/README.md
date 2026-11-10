# Glance no saradomin

O [Glance](https://github.com/glanceapp/glance) é o dashboard inicial do saradomin, em
`https://glance.saradomin.ftm.dev.br`, no namespace `dashboard`. Fica só pela LAN e pelo
tailnet: o Ingress existe apenas no entrypoint `websecure` e o nome não está no túnel da
Cloudflare (`terraform/cloudflare/main.tf`), então não há nada a aplicar no Terraform. O
AdGuard e o certificado wildcard de `*.saradomin.ftm.dev.br` já cobrem o nome novo.

O Glance não tem login próprio aqui, como os outros painéis internos; quem chega nele
já está na LAN ou no tailnet. Também não usa secrets.

## Página Saradomin

- **Busca** no topo (DuckDuckGo, com os atalhos `!yt`, `!gh`, `!r` e `!k8s`).
- **Clima** de Erechim (Open-Meteo) e **mercado**: MUND11 e dólar em reais, pelo Yahoo
  Finance. Para trocar o ativo (por exemplo pelo `VT`), use o símbolo do Yahoo; os da B3
  levam `.SA`, como `MUND11.SA`.
- **Relógio**, **calendário** e **server-stats**: CPU (load average), memória, temperatura e o
  uso do disco do `/data` do host, montado só leitura no pod.
- **Pendências**: um to-do salvo no navegador (localStorage), não no cluster.
- **Clusters**: saradomin e zamorak lado a lado, numa consulta só ao Prometheus daqui
  (o zamorak manda as métricas por remote write, com o label `cluster`): CPU, memória, disco
  raiz, pods rodando e com problema, restarts em 24h, rede, consumo pelo RAPL (só o
  saradomin tem) e há quanto tempo o nó está ligado.
- **Alertas** e **Pods com problema**: o Alertmanager está desligado, então os alertas vêm
  de `/api/v1/alerts` do próprio Prometheus (só os disparados, sem o `Watchdog`); os pods são
  os `Pending`/`Failed`/`Unknown` e os containers em `CrashLoopBackOff` ou com erro de imagem.
- **Serviços**: monitor checado direto nos Services do cluster (o pod não resolve
  `*.saradomin.ftm.dev.br`). O qBittorrent fica só nos favoritos, porque a NetworkPolicy dele
  libera a Web UI apenas para Sonarr, Radarr e Traefik.
- **Favoritos** do saradomin, do zamorak e dos painéis de fora (GitHub, Cloudflare, Tailscale,
  Oracle Cloud).
- **Releases** das peças que rodam aqui. Sem token, a API do GitHub permite 60 requisições
  por hora; com o cache de 6h, a lista cabe com folga.

## Página Notícias

Blogs (selfh.st, Kubernetes e Cloudflare), Hacker News, Lobsters e os subreddits
r/selfhosted, r/homelab e r/kubernetes. O Reddit às vezes bloqueia acesso sem login; se a aba dele mostrar erro, o
resto da página não é afetado.

## Mudando a config

Edite `glance.yml`. O `configMapGenerator` põe o hash do conteúdo no nome do ConfigMap, então
o pod reinicia com a config nova quando o Argo CD sincroniza a `main`.

Para validar antes, com o binário do Glance (o mesmo da imagem):

```sh
glance -config clusters/saradomin/apps/glance/glance.yml config:validate
```

Uma config inválida faz o Glance sair na hora em que sobe, e a readiness segura o pod antigo.

Os widgets `custom-api` usam templates Go; um erro neles aparece dentro do próprio widget, não
derruba o Glance. A referência das funções está em
[docs/custom-api.md](https://github.com/glanceapp/glance/blob/main/docs/custom-api.md).

## Disco novo

O server-stats mostra o disco montado em `/data` no host. Se um disco novo passar a ser o
`/data`, ele aparece sem mudança aqui. Se for montado em outro caminho (por exemplo
`/mnt/exos`), adicione um `hostPath` somente leitura no `deployment.yaml`, montado no mesmo
caminho, e o mesmo caminho em `mountpoints` no `glance.yml`, com `hide: false`.
