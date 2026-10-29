# Mesa no saradomin

O [Mesa](https://github.com/FelipeMalacarne/mesa) é o console dos bancos dos dois clusters: um só, no saradomin, com o `postgres-main` daqui e o do zamorak lado a lado. Fica no namespace `databases`, em `https://mesa.saradomin.ftm.dev.br`, com login pelo Zitadel.

Além de explorar, consultar e alterar (sempre com revisão), o Mesa cria o banco de um app novo de uma vez: **Users & roles › App database**. Ele cria o role e o banco na hora e commita neste repositório a declaração deles, então o Argo e o cluster continuam iguais ao Git.

```text
navegador (LAN ou tailnet) ── Traefik websecure ──► mesa (databases) ── login ──► Zitadel (auth.ftm.dev.br)
                                                      │
     saradomin: postgres-main-rw.databases.svc ◄──────┤
     zamorak:   zamorak-postgres.databases.svc ◄──────┤  (saída Tailscale ─► tailnet ─► postgres-main-tailnet)
                                                      │
     GitHub: gielinor/main ◄── commits dos bancos ────┘  ──► Argo ─► CNPG + Secrets
```

## Como está montado

- **App:** a `Application` `mesa` (`application.yaml`) aponta para o chart `charts/mesa` do repositório do Mesa, na tag do release, com a imagem da mesma versão. Os values ficam na própria `Application`.
- **Login:** pelo Zitadel (`../zitadel`). Quem entra e com que papel é decidido lá, pelos roles do projeto `mesa`: `admin` (conexões e bancos novos), `editor` (altera dados e schema, sempre revisado) e `viewer` (só lê). Sem role, não entra. O Mesa não guarda senha de ninguém. A sessão dura 12 horas; a auditoria registra o e-mail de quem fez cada escrita.
- **Conexões:** `saradomin` e `zamorak`, declaradas nos values (`connections`). Aparecem como *declared*: ninguém edita pela tela, só aqui. As duas são `production`: o Mesa só lê até alguém destravar, e cada escrita mostra o SQL e pede o nome digitado.
- **Role:** `mesa`, superusuário, nos dois `postgres-main` (`managed.roles` em `../postgres/cluster.yaml` e em `clusters/zamorak/apps/postgres/cluster.yaml`). A proteção é a revisão do Mesa e os papéis do Zitadel, não o privilégio do role.
- **Dados do Mesa:** o banco `mesa` do `postgres-main` daqui (`../postgres/databases.yaml`), dentro do backup do R2.
- **Zamorak:** o CNPG de lá publica o primário no tailnet como `zamorak-postgres` (o Service `postgres-main-tailnet` do `Cluster`); aqui, `zamorak-postgres.yaml` é a saída. Nada passa pela Cloudflare.
- **Acesso:** o Ingress só existe no `websecure` do Traefik, que só a LAN e o tailnet alcançam.

## Bancos novos para apps

Em **Users & roles › App database** (só `admin`), nome do banco (`shop`) e namespace do app (`shop`). A revisão mostra o SQL e os arquivos; em produção, destrave e digite o nome. Depois de aplicar:

1. O Mesa commita na `main`, em `clusters/<cluster>/apps/postgres/mesa/`:
   - `databases/shop.yaml`: o `Database` do CNPG (`databaseReclaimPolicy: retain`);
   - `roles.yaml`: o role `shop`, acrescentado aos `managed.roles` do `postgres-main` por um patch;
   - `secrets/shop-secrets.yaml`, cifrado com o SOPS para a chave de `.sops.yaml`: a senha do role (`shop-db-secret`, em `databases`) e a conexão do app (`shop-db`, no namespace `shop`, com `DATABASE_URL`, `uri`, `username`, `password`, `host`, `port` e `dbname`);
   - `kustomization.yaml` e `ksops.yaml`, que o Mesa reescreve a cada banco.
2. O Mesa cria o role (com uma senha gerada que ninguém vê) e o banco na hora, auditados.
3. O Argo sincroniza: o CNPG adota o role e o banco que já existem, e o Secret `shop-db` aparece no namespace `shop`. No Deployment do app basta `envFrom: [{secretRef: {name: shop-db}}]`.

Se o SQL falhar depois do commit, o CNPG cria o role e o banco quando o Argo sincronizar. O namespace do app precisa existir (`../../namespaces.yaml`). O Mesa só escreve dentro de `mesa/`; os outros arquivos de `apps/postgres` continuam à mão, como os bancos que já existiam. `apps/postgres` agora põe `databases` só onde o manifesto não diz outro namespace (`namespace.yaml`), porque os Secrets dos apps vão para os namespaces deles.

Para apagar: tire os dois arquivos do banco em `mesa/` (o `Database` tem `retain`: o banco continua, o CNPG deixa de cuidar). Para trocar a senha: por enquanto à mão, no `sops` do arquivo do banco.

## Segredos (`secrets.yaml`, SOPS)

| Secret | O que guarda |
|---|---|
| `mesa-db-secret` | usuário e senha do role `mesa` daqui; o CNPG aplica no role e o Mesa lê como `MESA_SARADOMIN_PASSWORD` |
| `mesa` | o ambiente do Mesa: `MESA_APP_KEY`, `MESA_STORE_DSN`, `MESA_ZAMORAK_PASSWORD`, `MESA_OIDC_CLIENT_ID`, `MESA_OIDC_CLIENT_SECRET` e `MESA_GITHUB_TOKEN` |

Duas senhas aparecem em dois lugares; não mude uma sem a outra: a do role `mesa` daqui (`mesa-db-secret` e a `MESA_STORE_DSN`) e a do role `mesa` do zamorak (`MESA_ZAMORAK_PASSWORD` e o `mesa-db-secret` de `clusters/zamorak/apps/postgres/mesa-secrets.yaml`).

## Ativar (uma vez)

1. **Release do Mesa.** A `Application` aponta para a tag `v0.5.0` (a `v0.4.0` saiu antes do login e do provisionamento). Mergeie o PR do Mesa e publique `0.5.0` em Actions › release › Run workflow (versão `0.5.0`, *publish* marcado). Se a versão for outra, troque `targetRevision` e `image.tag` em `application.yaml`.
2. **Zitadel.** Em `https://auth.ftm.dev.br/ui/console`:
   - um projeto `mesa` com os roles `admin`, `editor` e `viewer`, e **Assert Roles on Authentication** ligado;
   - nele, uma aplicação **Web**, autenticação **Code** com client secret (Basic), redirect URI `https://mesa.saradomin.ftm.dev.br/auth/callback`;
   - em Authorizations, o seu usuário com o role `admin` no projeto `mesa`.
3. **GitHub.** Um token *fine-grained* com acesso só ao repositório `gielinor`: **Contents: Read and write** (e **Pull requests: Read and write** se um dia usar `pull_request: true`).
4. **Segredos.** `sops clusters/saradomin/apps/mesa/secrets.yaml` e troque os três `CHANGE_ME`: o client ID e o client secret do passo 2 e o token do passo 3.
5. **ACL do tailnet.** A saída daqui e o proxy do zamorak são `tag:k8s`. Libere a porta do Postgres entre eles:

   ```json
   {"action": "accept", "src": ["tag:k8s"], "dst": ["tag:k8s:5432"]}
   ```

6. **DNS.** Se o AdGuard Home responde `*.saradomin.ftm.dev.br` por nome, e não por curinga, acrescente `mesa.saradomin.ftm.dev.br`.
7. **Root do Argo.** O `saradomin-root` passa a ignorar o `externalName` da saída (o operador do Tailscale escreve nele). Aplique uma vez:

   ```sh
   kubectl --context=saradomin apply -f clusters/saradomin/argocd/root-application.yaml
   ```

8. **Merge na `main`.** O `zamorak-root` cria o role `mesa`, o Service `postgres-main-tailnet` e o componente `mesa` vazio; o `saradomin-root` cria o role e o banco `mesa`, os Secrets, a saída, o componente vazio e a `Application`.
9. **Conferir.**

   ```sh
   kubectl --context=zamorak -n databases get svc postgres-main-tailnet
   kubectl --context=saradomin -n databases get database postgres-main-mesa
   kubectl --context=saradomin -n databases get svc zamorak-postgres -o jsonpath='{.spec.externalName}{"\n"}'
   kubectl --context=saradomin -n databases rollout status deploy/mesa
   ```

   Em `https://mesa.saradomin.ftm.dev.br`: **Sign in with Zitadel**, e as duas conexões abrem. Em Settings › Account aparece o papel `admin`.

## Agentes (MCP)

O Mesa serve as ferramentas do `mesa-mcp` em `/mcp`, só leitura (`MESA_MCP_WRITES` desligado). Crie um token em Settings › API tokens; ele age com o seu papel:

```json
{ "mcpServers": { "mesa": { "url": "https://mesa.saradomin.ftm.dev.br/mcp",
  "headers": { "Authorization": "Bearer mesa_…" } } } }
```

## Atualizar

Troque `targetRevision` (`vX.Y.Z`) e `image.tag` (`X.Y.Z`) juntos em `application.yaml`.

## Pendências

- **CloudNativePG no Mesa.** O ADR 0010 do Mesa propõe mostrar instâncias, WAL e backups do R2, fazer backup sob demanda e restore pelo Mesa, e um `mesa-agent` no zamorak no lugar da exposição pelo tailnet.
- **Trocar a senha de um banco provisionado** pelo Mesa (hoje à mão, no `sops`).
- **TLS verificado** nas conexões (`verify-full` com o CA do CNPG) e **uma tag própria** no tailnet para o proxy do Postgres.
