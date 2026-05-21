# Gielinor

## Proposed Structure

```
gielinor/
  README.md
  justfile
  .sops.yaml

  clusters/
    saradomin/
      kustomization.yaml
      namespaces.yaml
      infrastructure.yaml
      apps.yaml

    zamorak/
      kustomization.yaml
      namespaces.yaml
      infrastructure.yaml
      apps.yaml

  apps/
    n8n/
      base/
      overlays/
        saradomin/

    postgres/
      base/
      overlays/
        saradomin/

    redis/
      base/
      overlays/
        saradomin/

    rabbitmq/
      base/
      overlays/
        saradomin/

    uptime-kuma/
      base/
      overlays/
        zamorak/

    webhook-relay/
      base/
      overlays/
        zamorak/

  infrastructure/
    traefik/
      base/
      overlays/
        saradomin/
        zamorak/

    coredns/
      overlays/
        saradomin/
        zamorak/

    tailscale/
      base/
      overlays/
        saradomin/
        zamorak/

    cert-manager/
      base/
      overlays/
        zamorak/

    longhorn/
      overlays/
        saradomin/

    monitoring/
      base/
      overlays/
        saradomin/
        zamorak/

    argocd/
      overlays/
        zamorak/

  secrets/
    saradomin/
    zamorak/

  terraform/
    cloudflare/
    oracle/

  docs/
    dns.md
    bootstrap.md
    recovery.md
```
