# Backup do postgres-main

O `postgres-main` do zamorak (mapa, vaultwarden, n8n) arquiva o WAL continuamente e faz um backup base por semana, no domingo às 03:17 de São Paulo, no bucket `gielinor-postgres-backups` do R2. A janela de recuperação é de 7 dias: o backup é para desastre (perder o nó, o disco ou a conta da Oracle), não para voltar no tempo. É o mesmo esquema do saradomin, com o plugin Barman Cloud do CNPG (`../../../infrastructure/cnpg/plugin-barman-cloud.yaml`); o README de lá explica o funcionamento e o restore em detalhe: `clusters/saradomin/apps/postgres/backup/README.md`.

O que muda aqui:

- **Pasta.** Os dois clusters se chamam `postgres-main`. O do saradomin fica em `postgres-main/` na raiz do bucket; este, em `zamorak/postgres-main/`.
- **Credenciais.** `secrets.yaml` é uma cópia do Secret do saradomin: o mesmo token, com Object Read & Write só nesse bucket. Quem tiver o token de um cluster consegue apagar o backup do outro; para separar, crie um token novo no painel do R2 e troque os dois valores com `sops clusters/zamorak/apps/postgres/backup/secrets.yaml`.
- **Retenção.** 7 dias, e não 30 como no saradomin. Com o base semanal, ficam uns dois backups base e o WAL entre eles.
- **Frequência.** Um backup base por semana, com um processo só (`jobs: 1`): o banco tem ~11 GB e o nó tem 2 vCPUs. O WAL contínuo cobre o resto, então o restore a um ponto no meio da semana repete mais WAL e demora mais, mas chega ao mesmo lugar. O primeiro backup sai assim que o `ScheduledBackup` é criado (`immediate: true`).

## Conferir

```sh
kubectl --context=zamorak -n databases rollout status deploy/plugin-barman-cloud
kubectl --context=zamorak -n databases get cluster postgres-main -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")]}'
kubectl --context=zamorak -n databases get backups
```

`ContinuousArchiving` deve estar `True` e o backup em `completed`. Se o arquivamento falhar, o WAL que não sai acumula no disco do nó; o motivo aparece em `kubectl --context=zamorak -n databases logs postgres-main-1 -c plugin-barman-cloud`, e comentar `backup` em `../kustomization.yaml` desliga tudo.

## Restaurar

Como no saradomin: um `Cluster` novo com `bootstrap.recovery`, sem sobrescrever o `postgres-main`. A diferença está no `externalClusters`, que aponta para a pasta do zamorak pelo mesmo `ObjectStore`:

```yaml
  externalClusters:
    - name: postgres-main
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: r2-backups
          serverName: postgres-main
```

Use a mesma imagem do `postgres-main` (Postgres 18) e um `storage.size` que caiba o banco.

Testado em 2026-11-25 no saradomin, com um `ObjectStore` temporário apontando para `s3://gielinor-postgres-backups/zamorak/` (as credenciais de lá são as mesmas): o banco de ~11 GB subiu em 3 minutos, com o WAL repetido até o último segmento arquivado, e as contagens das tabelas maiores do `mapa` bateram com a produção. Restaurar em outro cluster é assim, com o `barmanObjectName` apontando para esse `ObjectStore`.

## Desastre (nó novo)

Se o zamorak for recriado do zero, o `postgres-main` precisa nascer do backup, e não vazio. Antes do primeiro sync do Argo no nó novo, num PR:

1. Em `../cluster.yaml`, acrescente ao `spec` o `bootstrap.recovery` (com `source: postgres-main` e sem `recoveryTarget`, para ir até o último WAL) e o `externalClusters` da seção acima.
2. Em `cluster-plugin.yaml`, acrescente `serverName: postgres-main-2` aos `parameters`. O plugin recusa arquivar numa pasta que já tem WAL, e a pasta `postgres-main` é a que está sendo restaurada.

O nome do `Cluster` continua `postgres-main`, então os apps conectam sem mudar nada, e os roles com as senhas vêm dos Secrets daqui. Depois que o banco subir, o `bootstrap` pode sair do `cluster.yaml` (o CNPG só o usa na criação). O `serverName` fica: o próximo desastre restaura de `postgres-main-2`.

Confira o primeiro backup com `kubectl --context=zamorak -n databases get backups`. Quando o Argo sobe tudo junto, o `ScheduledBackup` cria o backup imediato antes de o helm-controller instalar o plugin, e ele falha com `requested plugin is not available` (aconteceu na primeira vez, em 2026-11-25). O CNPG não tenta de novo, e o próximo só sai no domingo. Nesse caso, crie um à mão:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: postgres-main-<data>
  namespace: databases
spec:
  cluster:
    name: postgres-main
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
```
