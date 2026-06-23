output "tunnel_token" {
  value     = module.cloudflare.tunnel_token
  sensitive = true
}

output "saradomin_tunnel_token" {
  value       = module.cloudflare.saradomin_tunnel_token
  sensitive   = true
  description = "Saradomin Cloudflare tunnel token"
}
