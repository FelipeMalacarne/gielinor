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
# serve aqui porque é acrescentado depois da WAF. /healthz fica aberto: o release do CI
# espera por ele a revisão nova antes de publicar o web. O token do Terraform precisa de
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
    expression  = "(http.host eq \"api.${var.mapa_zone}\" and cf.worker.upstream_zone ne \"${var.mapa_zone}\" and http.request.uri.path ne \"/healthz\")"
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