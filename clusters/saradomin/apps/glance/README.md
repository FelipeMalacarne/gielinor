# Glance no saradomin

O [Glance](https://github.com/glanceapp/glance) é o dashboard inicial do saradomin, em
`https://glance.saradomin.ftm.dev.br`, no namespace `dashboard`. Fica só pela LAN e pelo
tailnet: o Ingress existe apenas no entrypoint `websecure` e o nome não está no túnel da
Cloudflare (`terraform/cloudflare/main.tf`), então não há nada a aplicar no Terraform. O
AdGuard e o certificado wildcard de `*.saradomin.ftm.dev.br` já cobrem o nome novo.

O Glance não tem login próprio aqui, como os outros painéis internos; quem chega nele
já está na LAN ou no tailnet.

## O que tem na página

- **Relógio** e **server-stats**: CPU (load average), memória e o uso do disco do `/data`
  do host, montado só leitura no pod.
- **Releases** das peças que rodam aqui (k3s, Traefik, Argo CD, CNPG, Zitadel, Jellyfin, Arr).
  Sem token, a API do GitHub permite 60 requisições por hora, o que basta para essa lista.
- **Monitor** dos serviços, checado direto nos Services do cluster (o pod não resolve
  `*.saradomin.ftm.dev.br`). O qBittorrent fica só nos favoritos, porque a NetworkPolicy dele
  libera a Web UI apenas para Sonarr, Radarr e Traefik.
- **Favoritos** do saradomin e do zamorak.

## Mudando a config

Edite `glance.yml`. O `configMapGenerator` põe o hash do conteúdo no nome do ConfigMap, então
o pod reinicia com a config nova no próximo deploy:

```sh
kustomize build --enable-alpha-plugins --enable-exec clusters/saradomin/apps/glance
make apply CLUSTER=saradomin
```

Para validar antes, com o binário do Glance (o mesmo da imagem):

```sh
glance -config clusters/saradomin/apps/glance/glance.yml config:validate
```

Uma config inválida faz o Glance sair na hora em que sobe, e a readiness segura o pod antigo.

## Disco novo

O widget mostra o disco montado em `/data` no host. Se um disco novo passar a ser o `/data`,
ele aparece sem mudança aqui. Se for montado em outro caminho (por exemplo `/mnt/exos`), adicione
um `hostPath` somente leitura no `deployment.yaml`, montado no mesmo caminho, e o mesmo caminho
em `mountpoints` no `glance.yml`.
