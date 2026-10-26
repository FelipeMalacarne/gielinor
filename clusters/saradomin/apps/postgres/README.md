# Postgres do saradomin

Um único cluster CloudNativePG, `postgres-main` no namespace `databases`, para todos os apps do saradomin. É o mesmo desenho do zamorak. O operador está em `../../infrastructure/cnpg`.

Para conectar, use `postgres-main-rw.databases.svc:5432`, com `sslmode=require`: o CNPG liga TLS com um certificado próprio.

## Adicionar um app

1. Em `cluster.yaml`, acrescente um role em `managed.roles`, com `passwordSecret` apontando para `<app>-db-secret`.
2. Em `databases.yaml`, acrescente um `Database` com `owner` igual ao role.
3. Em `sops secrets.yaml`, acrescente o Secret `<app>-db-secret`, do tipo `kubernetes.io/basic-auth`, com `username`, `password` e o label `cnpg.io/reload: "true"`. Gere a senha com `openssl rand -hex 24`.
4. No Secret do próprio app, monte a URL com a mesma senha: `postgres://<app>:<senha>@postgres-main-rw.databases.svc:5432/<app>?sslmode=require`.

## Pendências

- **Backup:** ainda não existe. Antes de guardar dados que não podem se perder (as contas do lastro, a partir do M1 dele), ligue o Barman para o R2 neste `Cluster`.
- **Primeiro `make apply`:** o `Cluster` e o `Database` dependem dos CRDs que o operador instala, então o primeiro apply manual pode falhar neles. Rode de novo depois que o operador subir. O Argo resolve isso sozinho, com o retry e o `SkipDryRunOnMissingResource` do `saradomin-root`.
