# SearXNG no saradomin

O [SearXNG](https://docs.searxng.org) é um metabuscador: repassa a consulta a vários buscadores
(Google, Bing, DuckDuckGo e outros) e junta os resultados. Aqui ele é a busca na web do n8n
Assistant (`../n8n`), que o chama por `N8N_INSTANCE_AI_SEARXNG_URL` em
`http://searxng.automation.svc:8080`. Não precisa de chave de API.

Fica só dentro do cluster, sem Ingress. A NetworkPolicy aceita conexões só do pod do n8n e deixa
o SearXNG sair só para a internet.

`settings.yml` guarda só o que muda em relação aos padrões:

- O formato `json` está ligado, porque é o que o n8n consulta. Sem ele, a API responde 403.
- O limiter está desligado, porque pediria um Valkey e quem consulta é só o n8n.

A `secret_key` vem de `SEARXNG_SECRET`, em `secrets.yaml`.

## Atualizar

O Renovate atualiza a imagem uma vez por semana, às segundas de madrugada, com automerge. Os
buscadores mudam e quebram os scrapers do SearXNG com frequência, então vale ficar em dia. Se a
busca do Assistant parar de trazer resultado, veja os erros por buscador em `/stats/errors`:

```sh
kubectl --context=saradomin -n automation port-forward deploy/searxng 8080
# http://localhost:8080/stats/errors
```
