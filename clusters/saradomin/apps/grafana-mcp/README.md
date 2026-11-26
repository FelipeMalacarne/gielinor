# MCP do Grafana no saradomin

O Claude (os conectores do claude.ai, que as routines na nuvem usam, e o Claude Code) lê logs e
métricas dos dois clusters e edita dashboards pelo [mcp-grafana](https://github.com/grafana/mcp-grafana),
em `https://grafana-mcp.ftm.dev.br/mcp`. O Grafana continua sem rota pública. Os dados do zamorak
já chegam ao Prometheus e ao Loki daqui (`../../../zamorak/infrastructure/observability`).

Um pod, dois containers, no namespace `observability`:

- **`auth-proxy`** ([mcp-auth-proxy](https://github.com/sigbit/mcp-auth-proxy)): a única porta de
  entrada. É o servidor OAuth que o cliente MCP enxerga: metadados (RFC 9728 e RFC 8414), registro
  dinâmico de cliente, token. O login é delegado ao Zitadel (`auth.ftm.dev.br`), e só passa o
  `sub` em `OIDC_ALLOWED_USERS`. A allowlist é pelo `sub`, não pelo e-mail, porque o Zitadel tem
  registro aberto. **Com a lista vazia, o proxy deixa qualquer conta entrar.** O BoltDB com
  clientes e tokens e as chaves de assinatura ficam no PVC `grafana-mcp-data`.
- **`mcp-grafana`**: escuta só em `127.0.0.1:8000` e fala com o Grafana pelo Service, com o token
  do service account `claude-mcp`. O `--enabled-tools` deixa de fora o que não existe aqui
  (Tempo, Pyroscope, OnCall, Incident, renderer) e a chamada livre à API do Grafana.

## O que o Claude pode fazer

O limite real é a permissão do service account no Grafana, não a lista de ferramentas:

- **Papel Viewer**: lê dashboards, consulta o Prometheus e o Loki, vê regras de alerta.
- **Edit só na pasta "Claude"**: cria e edita dashboards ali, e só ali.

Os dashboards provisionados (os ConfigMaps com `grafana_dashboard: "1"` em
`../../infrastructure/observability`) continuam vindo do git. Para um rascunho da pasta Claude
virar permanente, o JSON vira ConfigMap num PR deste repositório. O que fica só na pasta Claude mora
no `grafana.db`, no PVC `local-path` do Grafana, **sem backup**.

## Ativar (uma vez)

1. **Grafana.** Crie o service account e a pasta, com o admin do Grafana
   (`grafana.saradomin.ftm.dev.br` pela LAN ou pelo tailnet), em Administration › Users and
   access › Service accounts:
   - service account `claude-mcp`, papel **Viewer**, e um token sem validade;
   - pasta `Claude` em Dashboards › New folder. Em Folder actions › Manage permissions, dê
     **Edit** ao service account `claude-mcp`.
2. **Zitadel** (`https://auth.ftm.dev.br/ui/console`). Crie o projeto `grafana-mcp` e, nele, a
   aplicação `grafana-claude`: Web, code flow com client secret, redirect
   `https://grafana-mcp.ftm.dev.br/.auth/oidc/callback`. Anote o client ID e o secret. A
   allowlist do proxy já barra outras contas. Para barrar também no Zitadel, ligue
   **Check authorization on authentication** no projeto e dê a você a autorização nele.
3. **Segredos.** Troque os três `TROCAR` em `secrets.yaml` (`sops edit secrets.yaml`) pelo
   token do passo 1 e pelo client ID e secret do passo 2.
4. **Túnel.** `make tf-plan` mostra a regra `grafana-mcp` no túnel do saradomin e o CNAME
   `grafana_mcp_dns`. Depois, `make tf-apply`.
5. **Cluster.** Com o merge na `main`, o `saradomin-root` cria o app. Acompanhe com
   `kubectl --context saradomin -n observability get pod -l app.kubernetes.io/name=grafana-mcp`.
6. **Confira de fora.** Sem token, o `/mcp` responde 401 com o `WWW-Authenticate` apontando para
   os metadados, e os metadados apontam para o próprio host:

   ```sh
   curl -si -X POST https://grafana-mcp.ftm.dev.br/mcp | grep -i www-authenticate
   curl -s https://grafana-mcp.ftm.dev.br/.well-known/oauth-protected-resource/mcp | jq
   ```

## Conectar

- **claude.ai** (e as routines): Settings › Connectors › Add custom connector, com a URL
  `https://grafana-mcp.ftm.dev.br/mcp`. Não precisa de client ID: o conector se registra sozinho
  no proxy. O login abre o Zitadel.
- **Claude Code**: `claude mcp add --transport http --scope user grafana https://grafana-mcp.ftm.dev.br/mcp`,
  depois `/mcp` para fazer o login.

## Cortar o acesso

O access token do proxy vale 24 horas, e o refresh token, 30 dias. Tirar o `sub` da allowlist só
barra o próximo login. Para cortar na hora, revogue o token do service account no Grafana: o MCP
para de alcançar qualquer coisa. Para derrubar todas as sessões do proxy, apague o PVC
`grafana-mcp-data` com o pod parado.
