# lastro no saradomin

Este diretório é o lado do cluster do [lastro](https://github.com/FelipeMalacarne/lastro):

- a `Application` do Argo CD, apontando para `deploy/k8s/overlays/saradomin` do repositório do lastro, que é público e não precisa de credencial;
- o Postgres próprio, em `postgres.yaml`;
- os Secrets, em `secrets.yaml`.

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

   A senha do Postgres já foi gerada e está em `lastro-postgres` e dentro da `LASTRO_DATABASE_URL`. Não mude uma sem a outra. Pluggy e Ollama ficam vazios até o M1 do lastro.

3. **Ligar.** Descomente `apps/lastro` em `clusters/saradomin/kustomization.yaml`. O `saradomin-root` do Argo cria a `Application`, o Postgres e os Secrets, e a `Application` sobe o app. Sem o Argo, use `make apply CLUSTER=saradomin`.

4. **Conferir.** `kubectl --context=saradomin -n lastro get pods` deve mostrar `postgres-0` e `lastro-…` prontos. Depois abra `https://lastro.ftm.dev.br`: o Access pede o login e, em seguida, a página mostra "Signed in as felipemalacarne012@gmail.com".

## Pendências

- **Backup do Postgres:** ainda não existe. Antes de sincronizar contas reais (M1 do lastro), agende um `pg_dump` para o R2, ou traga o CNPG para o saradomin, com o Barman.
- **Ollama:** `LASTRO_OLLAMA_URL` está vazio, então o lastro só usa regras. Quando a categorização chegar, aponte para o zaros por um endereço que o saradomin alcance.
