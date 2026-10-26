output "tunnel_token" {
  value     = module.cloudflare.tunnel_token
  sensitive = true
}

output "saradomin_tunnel_token" {
  value       = module.cloudflare.saradomin_tunnel_token
  sensitive   = true
  description = "Saradomin Cloudflare tunnel token"
}

output "lastro_access_aud" {
  value       = module.cloudflare.lastro_access_aud
  description = "AUD do app do Access do lastro: vai para LASTRO_CF_ACCESS_AUD"
}
