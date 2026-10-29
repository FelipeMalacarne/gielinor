# Mesa no saradomin

O [Mesa](https://github.com/FelipeMalacarne/mesa) é o console SQL dos bancos dos dois clusters: um só, no saradomin, com o `postgres-main` daqui e o do zamorak lado a lado. Fica no namespace `databases`, junto dos bancos, em `https://mesa.saradomin.ftm.dev.br`.

```text
navegador (LAN ou tailnet) ── Traefik websecure + login provisório ──► mesa (databases)
                                                                         │
     saradomin: postgres-main-rw.databases.svc:5432 ◄────────────────────┤
                                                                         │
     zamorak:   zamorak-postgres.databases.svc:5432 (saída Tailscale) ───┘
                  └─► tailnet ─► zamorak-postgres (proxy) ─► postgres-main-tailnet ─► primário
```

## Como está montado

- **App:** a `Application` `mesa` (`application.yaml`) aponta para o chart `charts/mesa` do repositório do Mesa, na tag do release, com a imagem da mesma versão. Os values ficam na própria `Application`.
- **Conexões:** `saradomin` e `zamorak`, declaradas nos values (`connections`). No Mesa aparecem como *declared*: ninguém edita nem apaga pela tela, só por aqui. As duas são `production`: o Mesa só lê até alguém destravar a conexão, e cada escrita mostra o SQL e pede o nome da conexão digitado. Dá para criar outras conexões pela tela, que ficam guardadas no banco do Mesa.
- **Role:** `mesa`, superusuário, nos dois `postgres-main` (`managed.roles` em `../postgres/cluster.yaml` e em `clusters/zamorak/apps/postgres/cluster.yaml`). Superusuário porque o Mesa administra roles, bancos e sessões dos apps; a proteção é a revisão do Mesa, não o privilégio do role.
- **Dados do Mesa:** o banco `mesa` do `postgres-main` daqui (`../postgres/databases.yaml`): conexões criadas pela tela, auditoria de cada escrita, histórico de queries. Entra no backup do R2 com o resto.
- **Zamorak:** o CNPG de lá publica o primário no tailnet como `zamorak-postgres` (um Service a mais do `Cluster`, `managed.services.additional`, do tipo `LoadBalancer` com a classe `tailscale`). Aqui, `zamorak-postgres.yaml` é a saída: um `ExternalName` que o operador do Tailscale aponta para o proxy dele. O TLS do Postgres vai por dentro do túnel do Tailscale; nada disso passa pela Cloudflare.
- **Acesso:** o Ingress só existe no entrypoint `websecure` do Traefik, que só a LAN e o tailnet alcançam. O túnel da Cloudflare entrega no `web` e não tem regra para este host. Na frente, um login provisório do Traefik (`middleware.yaml`), porque o Mesa ainda não tem login próprio.

## Segredos (`secrets.yaml`, SOPS)

| Secret | O que guarda |
|---|---|
| `mesa-db-secret` | usuário e senha do role `mesa` daqui; o CNPG aplica no role e o Mesa lê como `MESA_SARADOMIN_PASSWORD` |
| `mesa` | o ambiente do Mesa: `MESA_APP_KEY`, `MESA_STORE_DSN` (banco `mesa`, com a mesma senha do role) e `MESA_ZAMORAK_PASSWORD` |
| `mesa-web-auth` | usuário e senha do login provisório do Traefik |

Duas senhas aparecem em dois lugares; não mude uma sem a outra:

- a do role `mesa` daqui: `mesa-db-secret` e a `MESA_STORE_DSN`;
- a do role `mesa` do zamorak: `MESA_ZAMORAK_PASSWORD` e o `mesa-db-secret` de `clusters/zamorak/apps/postgres/mesa-secrets.yaml`.

A `MESA_APP_KEY` cifra as senhas das conexões criadas pela tela. Perdê-la é perder essas senhas (as conexões declaradas não dependem dela).

Para ler o login do Traefik:

```sh
sops decrypt clusters/saradomin/apps/mesa/secrets.yaml \
  | yq 'select(.metadata.name == "mesa-web-auth").stringData'
```

## Ativar (uma vez)

1. **Release do Mesa.** A `Application` aponta para a tag `v0.4.0`, a primeira com as conexões declaradas e o chart que as monta. Mergeie o branch `claude/gracious-pascal-5xjw35` do Mesa e publique `0.4.0` em Actions › release › Run workflow (versão `0.4.0`, *publish* marcado). Se a versão for outra, troque `targetRevision` e `image.tag` em `application.yaml`. Antes disso a `Application` só fica com erro de sync, sem tocar em nada.
2. **ACL do tailnet.** A saída daqui e o proxy do zamorak são `tag:k8s`. Libere a porta do Postgres entre eles, ao lado da regra da telemetria:

   ```json
   {"action": "accept", "src": ["tag:k8s"], "dst": ["tag:k8s:5432"]}
   ```

   Com grants, o equivalente é `{"src": ["tag:k8s"], "dst": ["tag:k8s"], "ip": ["tcp:5432"]}`.
3. **DNS.** Se o AdGuard Home responde `*.saradomin.ftm.dev.br` por nome, e não por curinga, acrescente `mesa.saradomin.ftm.dev.br` como os outros.
4. **Root do Argo.** O `saradomin-root` passa a ignorar o `externalName` da saída (o operador do Tailscale é quem escreve nele). A `Application` raiz não se atualiza sozinha, então aplique uma vez:

   ```sh
   kubectl --context=saradomin apply -f clusters/saradomin/argocd/root-application.yaml
   ```

5. **Merge na `main`.** O `zamorak-root` cria o role `mesa`, o Service `postgres-main-tailnet` e o proxy `zamorak-postgres`; o `saradomin-root` cria o role e o banco `mesa`, os Secrets, a saída e a `Application`, que sobe o Mesa.
6. **Conferir.**

   ```sh
   kubectl --context=zamorak -n databases get svc postgres-main-tailnet
   kubectl --context=saradomin -n databases get database postgres-main-mesa
   kubectl --context=saradomin -n databases get svc zamorak-postgres -o jsonpath='{.spec.externalName}{"\n"}'
   kubectl --context=saradomin -n databases rollout status deploy/mesa
   ```

   O `EXTERNAL-IP` do `postgres-main-tailnet` é o endereço no tailnet, e `zamorak-postgres` aparece em Machines com `tag:k8s`. O `externalName` deixa de ser `placeholder`. Em `https://mesa.saradomin.ftm.dev.br`, depois do login, as duas conexões abrem; *Test connection* mostra a latência até cada uma.

## Agentes (MCP)

O Mesa serve as mesmas ferramentas do `mesa-mcp` em `/mcp`, só leitura (`MESA_MCP_WRITES` desligado). Com o login provisório, o cliente manda o cabeçalho:

```json
{ "mcpServers": { "mesa": { "url": "https://mesa.saradomin.ftm.dev.br/mcp",
  "headers": { "Authorization": "Basic <base64 de usuario:senha>" } } } }
```

## Atualizar

Troque `targetRevision` (`vX.Y.Z`) e `image.tag` (`X.Y.Z`) juntos em `application.yaml`. O chart e a imagem saem do mesmo release.

## Pendências

- **Login no Mesa.** OIDC com o Zitadel (`../zitadel`), com quem entrou registrado na auditoria. Quando existir, sai o `middleware.yaml` e o `mesa-web-auth`.
- **CloudNativePG no Mesa.** O ADR 0010 do Mesa propõe ler os `Cluster` do CNPG pelo ServiceAccount (as conexões aparecem sozinhas), mostrar instâncias, WAL e backups do R2, respeitar os roles e `Database` declarados aqui, e fazer backup sob demanda e restore pelo próprio Mesa. Para o zamorak, um `mesa-agent` lá dentro que liga para cá, no lugar da exposição pelo tailnet.
- **TLS verificado.** As duas conexões usam `require` (cifra sem conferir o certificado; para o zamorak, o Tailscale já autentica as pontas). Com o CA do CNPG (`postgres-main-ca`) dá para subir para `verify-full` na local.
- **Tag própria no tailnet.** Hoje qualquer `tag:k8s` alcança a 5432 do proxy. Uma tag só para ele (`tailscale.com/tags` no Service) e outra para a saída daqui estreitam a ACL.
