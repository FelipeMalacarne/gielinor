output "tunnel_token" {
  value     = data.cloudflare_zero_trust_tunnel_cloudflared_token.zamorak_tunnel_token.token
  sensitive = true
}
