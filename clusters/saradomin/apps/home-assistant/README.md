# Home Assistant no saradomin

O [Home Assistant](https://www.home-assistant.io) roda em `https://home.saradomin.ftm.dev.br`, no
namespace `automation`. Fica só pela LAN e pelo tailnet: o Ingress existe apenas no entrypoint
`websecure`, e o nome não está no túnel da Cloudflare (`terraform/cloudflare/main.tf`). O AdGuard e
o certificado wildcard de `*.saradomin.ftm.dev.br` já cobrem o nome. O login é o do próprio Home
Assistant.

## Rede do host

O pod roda com `hostNetwork`, porque o pacote do Wake-on-LAN é broadcast e não sai da rede de pods.
Com isso, a porta 8123 fica no próprio saradomin, e o firewall do NixOS bloqueia o Traefik. O
`hosts/saradomin/settings.nix` do nix-config libera a porta só para a rede de pods (`10.42.0.0/16`),
como faz com a interface do AdGuard. Sem essa regra, o Ingress responde 504.

## Configuração

O `configuration.yaml` está no Git e entra no pod por um ConfigMap, montado só leitura. Ele tem o
que precisa existir antes da interface: o Traefik como proxy confiável e o switch do zaros. O resto
(local, integrações, usuários, automações) é feito pela interface e fica no PVC
`home-assistant-data`. Os editores de automações, scripts e cenas gravam em `automations.yaml`,
`scripts.yaml` e `scenes.yaml`, e o initContainer cria esses arquivos se faltarem.

O switch `zaros` liga o zaros pelo Wake-on-LAN, suspende pelo SSH e mostra o estado pelo ping em
`10.10.0.20`. Esse IP precisa ser fixo no DHCP do roteador; se mudar, o switch mostra o zaros
desligado mesmo ligado, e o SSH não chega nele.

Para suspender, o Home Assistant entra no zaros como `felipe`, com a chave do Secret
`home-assistant-ssh` (`secrets.yaml`). No zaros, o `authorized_keys` prende essa chave ao comando
`sudo systemctl suspend`, e o sudo libera só esse comando sem senha (`hosts/zaros/settings.nix` do
nix-config). Com a chave, não dá para abrir um shell. A chave pública fica em
`keys/home-assistant.pub` do nix-config, e a chave de host do zaros fica fixada em `known_hosts`.
Se o zaros for reinstalado, atualize o `known_hosts` com o `/etc/ssh/ssh_host_ed25519_key.pub`
novo.

O PVC é `local-path`, sem backup fora do saradomin. Os backups do próprio Home Assistant
(Configurações › Sistema › Backups) também ficam no mesmo disco.

A versão está fixada no `deployment.yaml`, e o Renovate a atualiza (`renovate.json` na raiz). Os
patches entram com automerge. A versão de cada mês vira um PR esperando revisão: leia as breaking
changes nas notas antes do merge.

## Ativar (uma vez)

1. **nix-config.** Aplique no saradomin, para a regra da porta 8123 entrar, e no zaros, para a
   chave do Home Assistant e a regra do sudo entrarem.
2. **Cluster.** Com o merge na `main`, o `saradomin-root` sobe o app.
3. **Dono.** Abra `https://home.saradomin.ftm.dev.br` e crie a conta de dono logo depois do deploy:
   até ela existir, quem abrir o endereço primeiro cria o dono. No onboarding, a localização da casa
   cria a integração de clima (Met.no).
4. **Celular.** No app Companion, use o mesmo endereço. Fora de casa, ele funciona pelo tailnet.
