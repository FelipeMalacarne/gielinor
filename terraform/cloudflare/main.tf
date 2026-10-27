provider "cloudflare" {
  api_token = var.api_token
}

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5.8.2"
    }
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "zamorak_tunnel" {
  account_id = var.account_id
  name       = "Terraform zamorak tunnel"
  config_src = "cloudflare"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "zamorak_tunnel_token" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.zamorak_tunnel.id
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "zamorak_tunnel_config" {
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.zamorak_tunnel.id
  account_id = var.account_id
  config = {
    ingress = [
      {
        hostname = "n8n.${var.zone}"
        service  = "http://traefik.kube-system.svc.cluster.local:80"
      },
      {
        hostname = "whoami.${var.zone}"
        service  = "http://traefik.kube-system.svc.cluster.local:80"
      },
      {
        hostname = "vault.${var.zone}"
        service  = "http://traefik.kube-system.svc.cluster.local:80"
      },
      {
        hostname = "argocd.${var.zone}"
        service  = "http://traefik.kube-system.svc.cluster.local:80"
      },
      {
        # API do Mapa do Acerto: privada ao Worker do web (X-Internal-Token no binário;
        # cloudflare_ruleset.mapa_waf bloqueia na borda o que não vem do Worker).
        hostname = "api.${var.mapa_zone}"
        service  = "http://traefik.kube-system.svc.cluster.local:80"
      },
      {
        # Só o /healthz da API do mapa (o Ingress do mapa só roteia esse caminho neste host),
        # fora da zona do mapa: lá o Bot Fight Mode barra o curl do release do CI e não
        # aceita exceção no plano Free.
        hostname = "mapa-healthz.${var.zone}"
        service  = "http://traefik.kube-system.svc.cluster.local:80"
      },
      {
        service = "http_status:404"
      }
    ]
  }
}

resource "cloudflare_dns_record" "mapa_api_dns" {
  zone_id = var.mapa_zone_id
  name    = "api.${var.mapa_zone}"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.zamorak_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "[terraform] zamorak mapa-do-acerto api"
}

resource "cloudflare_dns_record" "mapa_healthz_dns" {
  zone_id = var.zone_id
  name    = "mapa-healthz.${var.zone}"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.zamorak_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "[terraform] zamorak mapa-do-acerto api /healthz (release do CI)"
}

# O apex é custom domain do Worker mapa-web (wrangler.jsonc no repo do mapa). O `www` só
# existe para a regra abaixo redirecionar na borda, sem invocar o Worker: 100:: é o
# endereço de descarte que o Cloudflare recomenda para hostname só com redirect.
resource "cloudflare_dns_record" "mapa_www_dns" {
  zone_id = var.mapa_zone_id
  name    = "www.${var.mapa_zone}"
  content = "100::"
  type    = "AAAA"
  ttl     = 1
  proxied = true
  comment = "[terraform] mapa-do-acerto www -> apex (redirect rule)"
}

# Só pode haver um ruleset por fase na zona: se o apply falhar dizendo que já existe,
# a regra foi criada pelo painel e precisa ser importada ou apagada antes.
resource "cloudflare_ruleset" "mapa_redirects" {
  zone_id     = var.mapa_zone_id
  name        = "mapa redirects"
  description = "Redirects da zona ${var.mapa_zone}"
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  rules = [{
    ref         = "www_to_apex"
    description = "www.${var.mapa_zone} -> ${var.mapa_zone}"
    expression  = "(http.host eq \"www.${var.mapa_zone}\")"
    action      = "redirect"
    action_parameters = {
      from_value = {
        status_code           = 301
        preserve_query_string = true
        target_url = {
          expression = "concat(\"https://${var.mapa_zone}\", http.request.uri.path)"
        }
      }
    }
  }]
}

# A API só atende o Worker do web (ADR-016 do mapa). cf.worker.upstream_zone é a zona dona
# do Worker que fez a subrequisição, vazio para quem chega direto; o header CF-Worker não
# serve aqui porque é acrescentado depois da WAF. O release do CI lê o /healthz por
# mapa-healthz.ftm.dev.br, então aqui não há exceção. O token do Terraform precisa de
# Zone > Zone WAF > Edit na zona do mapa.
resource "cloudflare_ruleset" "mapa_waf" {
  zone_id     = var.mapa_zone_id
  name        = "mapa waf"
  description = "Regras de WAF da zona ${var.mapa_zone}"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules = [{
    ref         = "api_only_worker"
    description = "api.${var.mapa_zone} só para o Worker do web"
    expression  = "(http.host eq \"api.${var.mapa_zone}\" and cf.worker.upstream_zone ne \"${var.mapa_zone}\")"
    action      = "block"
  }]
}

resource "cloudflare_dns_record" "whoami_dns" {
  zone_id = var.zone_id
  name    = "whoami.${var.zone}"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.zamorak_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "[terraform] zamorak whoami"
}

resource "cloudflare_dns_record" "vault_dns" {
  zone_id = var.zone_id
  name    = "vault.${var.zone}"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.zamorak_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "[terraform] zamorak vaultwarden"
}

resource "cloudflare_dns_record" "n8n_dns" {
  zone_id = var.zone_id
  name    = "n8n.${var.zone}"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.zamorak_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "[terraform] zamorak n8n"
}

resource "cloudflare_dns_record" "argocd_dns" {
  zone_id = var.zone_id
  name    = "argocd.${var.zone}"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.zamorak_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "[terraform] zamorak argocd"
}

resource "cloudflare_zero_trust_access_application" "argocd" {
  account_id                 = var.account_id
  name                       = "Zamorak Argo CD"
  domain                     = "argocd.${var.zone}"
  type                       = "self_hosted"
  session_duration           = "12h"
  http_only_cookie_attribute = true
  same_site_cookie_attribute = "strict"

  policies = [{
    name       = "Allow Felipe"
    precedence = 1
    decision   = "allow"
    include = [{
      email = {
        email = "felipemalacarne012@gmail.com"
      }
    }]
  }]
}

# Webhook do GitHub para o Argo CD (push no mapa-do-acerto → refresh na hora). O caminho
# mais específico ganha do app acima; quem autentica é o Argo, pelo HMAC do segredo do
# webhook (Secret argocd-webhook). Sem segredo configurado, o Argo aceita qualquer POST.
resource "cloudflare_zero_trust_access_application" "argocd_webhook" {
  account_id       = var.account_id
  name             = "Zamorak Argo CD webhook"
  domain           = "argocd.${var.zone}/api/webhook"
  type             = "self_hosted"
  session_duration = "24h"

  policies = [{
    name       = "Bypass GitHub webhook"
    precedence = 1
    decision   = "bypass"
    include = [{
      everyone = {}
    }]
  }]
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "saradomin_tunnel" {
  account_id = var.account_id
  name       = "Terraform saradomin tunnel"
  config_src = "cloudflare"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "saradomin_tunnel_token" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.saradomin_tunnel.id
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "saradomin_tunnel_config" {
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.saradomin_tunnel.id
  account_id = var.account_id
  config = {
    ingress = [
      {
        hostname = "whoami.saradomin.${var.zone}"
        service  = "http://traefik.networking.svc.cluster.local:80"
      },
      {
        hostname = "claw.${var.zone}"
        service  = "http://traefik.networking.svc.cluster.local:80"
      },
      {
        hostname = "jellyfin.${var.zone}"
        service  = "http://traefik.networking.svc.cluster.local:80"
      },
      {
        hostname = "request.${var.zone}"
        service  = "http://traefik.networking.svc.cluster.local:80"
      },
      {
        hostname = "lastro.${var.zone}"
        service  = "http://traefik.networking.svc.cluster.local:80"
      },
      {
        hostname = "auth.${var.zone}"
        service  = "http://traefik.networking.svc.cluster.local:80"
      },
      {
        service = "http_status:404"
      }
    ]
  }
}

resource "cloudflare_dns_record" "whoami_saradomin_dns" {
  zone_id = var.zone_id
  name    = "whoami.saradomin.${var.zone}"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.saradomin_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "[terraform] saradomin whoami"
}

resource "cloudflare_dns_record" "openclaw_saradomin_dns" {
  zone_id = var.zone_id
  name    = "claw.${var.zone}"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.saradomin_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "[terraform] saradomin openclaw"
}

resource "cloudflare_dns_record" "jellyfin_saradomin_dns" {
  zone_id = var.zone_id
  name    = "jellyfin.${var.zone}"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.saradomin_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "[terraform] saradomin jellyfin"
}

resource "cloudflare_dns_record" "seerr_saradomin_dns" {
  zone_id = var.zone_id
  name    = "request.${var.zone}"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.saradomin_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "[terraform] saradomin seerr"
}

resource "cloudflare_dns_record" "lastro_saradomin_dns" {
  zone_id = var.zone_id
  name    = "lastro.${var.zone}"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.saradomin_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "[terraform] saradomin lastro"
}

# Zitadel (clusters/saradomin/apps/zitadel), sem Access na frente: os clients OAuth (o CLI do
# lastro, o conector do Claude) precisam alcançar discovery, token e device direto. O console
# se protege com o login do próprio Zitadel.
resource "cloudflare_dns_record" "auth_saradomin_dns" {
  zone_id = var.zone_id
  name    = "auth.${var.zone}"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.saradomin_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "[terraform] saradomin zitadel"
}

# O lastro confere o JWT do Access em toda rota (menos /healthz e /readyz, que só o kubelet usa).
# O AUD deste app vai para LASTRO_CF_ACCESS_AUD em clusters/saradomin/apps/lastro/secrets.yaml
# (output lastro_access_aud). SameSite lax, e não strict como no Argo CD, para que um link vindo de
# fora (um alerta por email, por exemplo) abra o app já logado.
resource "cloudflare_zero_trust_access_application" "lastro" {
  account_id                 = var.account_id
  name                       = "Saradomin lastro"
  domain                     = "lastro.${var.zone}"
  type                       = "self_hosted"
  session_duration           = "24h"
  http_only_cookie_attribute = true
  same_site_cookie_attribute = "lax"

  policies = [{
    name       = "Allow Felipe"
    precedence = 1
    decision   = "allow"
    include = [{
      email = {
        email = "felipemalacarne012@gmail.com"
      }
    }]
  }]
}
