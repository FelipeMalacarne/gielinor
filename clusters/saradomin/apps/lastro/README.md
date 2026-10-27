# lastro no saradomin

Este diretório é o lado do cluster do [lastro](https://github.com/FelipeMalacarne/lastro):

- a `Application` do Argo CD, apontando para `deploy/k8s/overlays/saradomin` do repositório do lastro, que é público e não precisa de credencial;
- o Secret do app, em `secrets.yaml`.

O banco não fica aqui: é o `lastro` do cluster compartilhado `postgres-main` (`../postgres`), com role, `Database` e senha lá.

Como o app roda (Deployment com a migration no initContainer, Service, Ingress, CronJob do sync) está no repositório do lastro. O CI dele publica `ghcr.io/felipemalacarne/lastro:<sha>` a cada merge na `main` e grava esse tag no overlay, então o Argo sobe a versão nova sozinho. A imagem é pública no GHCR, por isso não há `imagePullSecret`.

O namespace `lastro` está em `../../namespaces.yaml`, junto dos outros.

## Ativar (uma vez)

1. **Cloudflare.** `make tf-plan` e `make tf-apply` criam a regra `lastro.ftm.dev.br` no túnel do saradomin, o CNAME e o app do Access, liberado só para felipemalacarne012@gmail.com. Depois leia o AUD:

   ```sh
   . ./r2-secrets.sh && terraform -chdir=terraform output -raw lastro_access_aud
   ```

2. **Segredos.** Abra `sops clusters/saradomin/apps/lastro/secrets.yaml` e troque os dois `CHANGE_ME` de `lastro-secrets`:
   - `LASTRO_CF_ACCESS_TEAM_DOMAIN`: o domínio do time do Zero Trust (`<time>.cloudflareaccess.com`, em Zero Trust › Settings › Team name).
   - `LASTRO_CF_ACCESS_AUD`: a saída do passo 1.

   A senha do banco já foi gerada. Ela está na `LASTRO_DATABASE_URL` e no `lastro-db-secret` de `../postgres/secrets.yaml`: não mude uma sem a outra. Pluggy e Ollama ficam vazios até o M1 do lastro.

3. **Ligar.** Descomente `apps/lastro` em `clusters/saradomin/kustomization.yaml`. O `saradomin-root` do Argo cria a `Application` e o Secret, e a `Application` sobe o app. Sem o Argo, use `make apply CLUSTER=saradomin`. O `postgres-main` e o banco `lastro` já sobem antes, junto com `apps/postgres`.

4. **Conferir.** `kubectl --context=saradomin -n databases get cluster,database` deve mostrar o `postgres-main` saudável e o `Database` `postgres-main-lastro` aplicado. `kubectl --context=saradomin -n lastro get pods` deve mostrar o `lastro-…` pronto. Depois abra `https://lastro.ftm.dev.br`: o Access pede o login e, em seguida, a página mostra "Signed in as felipemalacarne012@gmail.com".

## Sincronizar com o Meu Pluggy (M1 do lastro)

O CronJob `lastro-sync` roda `lastro sync` quatro vezes por dia (minuto 17 de 0h, 6h, 12h e 18h de São Paulo). As credenciais do Pluggy ficam num Secret à parte, `lastro-pluggy`, em `pluggy-secrets.yaml`, que o lastro lê depois de `lastro-secrets`.

- `LASTRO_PLUGGY_CLIENT_ID` e `LASTRO_PLUGGY_CLIENT_SECRET`: Pluggy Dashboard › Applications.
- `LASTRO_PLUGGY_ITEM_IDS`: os ids dos itens, separados por vírgula. A API do Meu Pluggy não lista itens (`LIST_ITEMS_FEATURE_NOT_ENABLED`): cada banco conectado pelo MeuPluggy em Applications › a aplicação › Demo › Connect Account aparece em Connected Items, com o id.

Para trocar uma delas (por exemplo, ao gerar um Client Secret novo ou conectar outro banco): `sops clusters/saradomin/apps/lastro/pluggy-secrets.yaml`. Para rodar um sync na hora, sem esperar o horário:

```sh
kubectl --context=saradomin -n lastro create job --from=cronjob/lastro-sync lastro-sync-now
kubectl --context=saradomin -n lastro logs -f job/lastro-sync-now
```

A saída tem uma linha por banco, com contas e transações importadas; o primeiro sync de cada item lê todo o histórico que o Pluggy guarda. A autorização do Meu Pluggy vale um ano (a atual vai até 10/04/2027): duas semanas antes, o lastro avisa na tela; para renovar, repita o Connect Account, e confira se o id do item mudou.

## Pendências
- **Ollama:** `LASTRO_OLLAMA_URL` está vazio, então o lastro só usa regras. Quando a categorização chegar, aponte para o zaros por um endereço que o saradomin alcance.
