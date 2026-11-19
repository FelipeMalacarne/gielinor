# Sandbox do n8n Assistant

O n8n Assistant (`../n8n`) roda código num sandbox isolado. Este diretório instala o chart
oficial [`n8n-sandbox-service`](https://github.com/n8n-io/n8n-sandbox-service) no namespace
`n8n-sandbox`, por um `HelmChart` do k3s. São dois componentes:

- **API** (`n8n-sandbox-api`, HTTP na porta 8080): só o pod do n8n alcança, pela NetworkPolicy do
  chart. O n8n se autentica com o `api-keys` de `n8n-sandbox-auth`.
- **Runner** (`n8n-sandbox-privileged-runner`): um Docker-in-Docker que sobe um container por
  sandbox, com a imagem `n8nio/n8n-sandbox-service-sandbox`. Ele se registra na API por gRPC com
  mTLS, e os certificados vêm da CA própria do namespace (`ca.yaml`).

## Isolamento

O n8n recomenda o Sysbox, que não serve aqui. O instalador do Sysbox exige nós Ubuntu e escreve
no `/usr` e no `/etc` do host, que no NixOS são do Nix. O Sysbox também não está no nixpkgs. O
suporte ao k3s é uma issue aberta ([nestybox/sysbox#841](https://github.com/nestybox/sysbox/issues/841)),
e o Sysbox 0.7 com containerd 2.x falha ao criar pods no k3s
([#1006](https://github.com/nestybox/sysbox/issues/1006)).

A isolação `privileged` com user namespaces (`hostUsers: false`) também não funciona no
saradomin. Testado em 2026-11-19, com k3s 1.35 e containerd 2.2.5: o pod enxerga a árvore de
cgroups do host, com dono `nobody` e sem delegação, e o Docker-in-Docker para na partida
(`mkdir /sys/fs/cgroup/init: Permission denied`). O `crun` do k3s não aceita user namespaces.

Por isso o runner é `privileged` puro. As camadas que restam:

- O código do Assistant não roda no runner. Roda nos containers que o runner cria, com
  `--cap-drop ALL`, `no-new-privileges`, limites de memória, CPU e PIDs, sem comunicação entre
  sandboxes e sem IPv6. Para chegar ao host, o código precisa escapar desse container (um
  exploit de kernel ou do runc). Só então o `privileged` do runner vira root no saradomin.
- A saída do runner, e com ela a dos sandboxes, passa por `networkpolicy.yaml`: DNS, a API e a
  internet, nunca a LAN, a rede do cluster ou a tailnet. É o que segura um prompt injection que
  tente alcançar o Postgres ou os painéis internos.
- O runner tem limites de 2 CPU e 3 GB. O Docker interno fica num `emptyDir` de 20Gi.

Um passo além seria rodar o runner numa microVM com Kata Containers
(`runner.privileged.runtime.runtimeClassName` no `values.yaml`). Assim o `privileged` vale só
dentro da VM. Isso pede o Kata no containerd do k3s, pelo `nix-config`.

## Conferir

```sh
kubectl --context=saradomin -n n8n-sandbox get pods,certificates
kubectl --context=saradomin -n n8n-sandbox describe statefulset n8n-sandbox-privileged-runner
```

Se o runner não aparecer, os eventos do StatefulSet dizem por quê. Depois, peça algo ao Assistant que rode código. O primeiro sandbox demora mais, porque o
runner baixa a imagem do sandbox.

## Atualizar

O `version` do `helmchart.yaml` fixa o chart, e as imagens seguem o `appVersion` dele. Para
atualizar, veja os releases do [repositório](https://github.com/n8n-io/n8n-sandbox-service).
