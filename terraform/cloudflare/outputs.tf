output "tunnel_token" {
  value     = data.cloudflare_zero_trust_tunnel_cloudflared_token.zamorak_tunnel_token.token
  sensitive = true
}

output "saradomin_tunnel_id" {
  value       = cloudflare_zero_trust_tunnel_cloudflared.saradomin_tunnel.id
  description = "Saradomin Cloudflare tunnel ID"
}

output "saradomin_tunnel_token" {
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.saradomin_tunnel_token.token
  sensitive   = true
  description = "Saradomin Cloudflare tunnel token"
}
