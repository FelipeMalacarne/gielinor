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
        hostname = "whoami.${var.zone}"
        service  = "http://traefik.kube-system.svc.cluster.local:80"
      },
      {
        service = "http_status:404"
      }
    ]
  }
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
