terraform {
  required_version = ">= 1.0"

  backend "s3" {
    bucket                      = "gielinor-tfstate"
    key                         = "terraform/state/gielinor.tfstate"
    region                      = "auto"
    endpoints = {
      s3 = "https://0eba569b4bb5e3bb00cdeae6772f44d8.r2.cloudflarestorage.com"
    }
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }
}

module "cloudflare" {
  source     = "./cloudflare"
  api_token  = var.cloudflare_api_token
  account_id = var.cloudflare_account_id
  zone_id    = var.cloudflare_zone_id
  zone       = var.cloudflare_zone
}
