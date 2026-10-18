variable "api_token" {
  description = "Cloudflare API Token"
  type        = string
  sensitive   = true
}

variable "account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

variable "zone_id" {
  description = "Zone ID for ftm.dev.br"
  type        = string
}

variable "zone" {
  description = "Domain (e.g. ftm.dev.br)"
  type        = string
}

variable "mapa_zone_id" {
  description = "Zone ID for mapadoacerto.com.br (zona separada de ftm.dev.br)"
  type        = string
}

variable "mapa_zone" {
  description = "Domain of Mapa do Acerto"
  type        = string
  default     = "mapadoacerto.com.br"
}
