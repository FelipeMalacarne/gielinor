# estudio no saradomin

O n8n não renderiza: a imagem dele não tem Chromium, e o node Execute Command vem desligado na
2.x. Este é o worker de mídia do [estudio](https://github.com/FelipeMalacarne/estudio), chamado
pelo n8n (`../n8n`). A primeira rota é o `/render`, que renderiza os shorts; as próximas
(`/transcrever` para a narração do canal tech, `/quadro` para capas) entram como rotas próprias,
cada uma com a entrada validada. Ele não roda comando arbitrário: para isso existe o
`../n8n-sandbox`. A API e o comportamento estão no `scripts/servidor.ts` do estudio.

Fica só dentro do cluster, sem Ingress, em `http://estudio.automation.svc:8080`. A
NetworkPolicy aceita conexões só do pod do n8n e deixa o worker sair só para a internet (o GitHub e
o registry do npm). Toda rota, menos `GET /saude`, pede o cabeçalho `X-Estudio-Token` com o
`ESTUDIO_TOKEN` de `estudio-secrets`. O callback do fim do lote também sai para a internet,
então ele chega no n8n pela URL pública (`$execution.resumeUrl`).

A imagem é a da [Playwright](https://mcr.microsoft.com/en-us/artifact/mar/playwright), fixada por
tag e digest. Ela traz o Node, que roda o TypeScript do servidor sem transpilar, e as dependências
de sistema do Chromium. Não há build de imagem: o código vem do repositório.

- Na partida, o initContainer `baixa-servidor` baixa o tarball da `main` do estudio e o extrai em
  `/dados/servidor`. Para atualizar o servidor, reinicie o pod.
- Cada render usa o código do commit pedido, baixado em `/dados/fontes/<sha>`. Os `node_modules`
  ficam em `/dados/modulos`, um por `package-lock.json`.

`/dados` é um PVC `local-path` de 20Gi. A fila de renders vive na memória do pod: se ele
reiniciar, o n8n pede de novo, e o que já está em disco não é renderizado outra vez.

## Ativar (uma vez)

1. **PAT.** No GitHub, em Settings › Developer settings › Personal access tokens › Fine-grained
   tokens, crie um token com:
   - Resource owner: `FelipeMalacarne`;
   - Repository access: *Only select repositories*, só o `FelipeMalacarne/estudio`;
   - Repository permissions: *Contents: Read-only*. O *Metadata: Read-only* vem junto, obrigatório.
2. **Secret.** Troque o `GITHUB_TOKEN` (hoje `TROCAR-PAT-fine-grained-contents-read-estudio`)
   pelo token novo:

   ```sh
   sops clusters/saradomin/apps/estudio/secrets.yaml
   ```

   O `sops` abre o arquivo decifrado no editor e o cifra de novo ao salvar. Faça o commit só do
   `secrets.yaml`.
3. **Cluster.** O `servidor.ts` precisa estar na `main` do estudio antes do deploy. Com o merge na
   `main` daqui, o `saradomin-root` sobe o app. Para aplicar na mão:
   `make apply CLUSTER=saradomin`.
4. **n8n.** Crie no n8n uma credencial *Header Auth* com o nome `X-Estudio-Token` e o valor de:

   ```sh
   sops -d --extract '["stringData"]["ESTUDIO_TOKEN"]' clusters/saradomin/apps/estudio/secrets.yaml
   ```

## Conferir

```sh
kubectl --context=saradomin -n automation get pods -l app.kubernetes.io/name=estudio
kubectl --context=saradomin -n automation logs deploy/estudio -c baixa-servidor
kubectl --context=saradomin -n automation exec deploy/n8n -c n8n -- \
  wget -qO- http://estudio.automation.svc:8080/saude
```

Se o pod ficar em `Init:CrashLoopBackOff`, o log do `baixa-servidor` mostra a resposta do GitHub.
Um 401 ou 404 quer dizer que o PAT expirou ou não alcança o estudio.

## Atualizar

- **Servidor:** `kubectl --context=saradomin -n automation rollout restart deploy/estudio`.
- **Imagem:** o Renovate abre um PR quando sai uma versão nova da Playwright (`renovate.json` na
  raiz). Ele fica esperando revisão, porque a imagem traz o Node que roda o servidor e o render.
- **PAT:** fine-grained tokens expiram. Troque-o com o passo 2 e reinicie o pod.
