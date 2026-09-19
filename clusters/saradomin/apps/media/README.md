# Saradomin media and Switch library

The media stack is deployed in the `media` namespace:

- Radarr, Sonarr, Prowlarr, qBittorrent, Bazarr, FlareSolverr
- Jellyfin and Seerr
- Buildarr, which reconciles the Arr API configuration from `buildarr-config.yaml`
- AeroFoil, serving the Switch library at `aerofoil.saradomin`

Buildarr owns the Arr API configuration for root folders, qBittorrent download clients,
Prowlarr application links, and the FlareSolverr proxy. Indexer definitions, Bazarr,
Jellyfin, Seerr, and AeroFoil's library metadata still require their application-specific
initial setup because those projects do not expose a compatible declarative controller here.

## One-time host preparation

On the `saradomin` node, create the directories and make them writable by UID/GID 1001:

```sh
sudo mkdir -p /data/media/movies /data/media/tv
sudo mkdir -p /data/downloads/complete /data/downloads/incomplete
sudo mkdir -p /data/switch/games /data/switch/downloads /data/switch/conversion-tmp
sudo chown -R 1001:1001 /data
sudo chmod -R 775 /data
```

The shared `/data` mount is intentional: Radarr and Sonarr can hardlink completed downloads
into the media library without crossing filesystems.

## Access

Private services are routed through the existing Tailscale-backed Traefik service:

- `radarr.saradomin`, `sonarr.saradomin`, `prowlarr.saradomin`
- `bazarr.saradomin`, `qbit.saradomin`, `jellyfin.saradomin`
- `seerr.saradomin`, `aerofoil.saradomin`, `argocd.saradomin`

The AeroFoil workload also has a direct LAN `LoadBalancer` on port `8465`. Reserve a stable
DHCP lease for the Saradomin node and configure CyberFoil with
`http://<saradomin-lan-ip>:8465`; this keeps Switch traffic on the LAN and avoids both
Tailscale and the Cloudflare tunnel. `*.saradomin` is a Tailscale split-DNS zone and is not
reachable from a stock Nintendo Switch. If the K3s ServiceLB is disabled, use the explicit
NodePort `http://<saradomin-lan-ip>:30465` instead.

The Terraform Cloudflare tunnel exposes Jellyfin at `jellyfin.ftm.dev.br` and Seerr at
`request.ftm.dev.br`. Apply those Terraform changes separately with `make tf-plan` and review
them before `make tf-apply`.

## Argo CD bootstrap

Argo CD is included in the Saradomin deployment but needs a one-time bootstrap because its
repo-server must receive the SOPS age key outside Git:

```sh
make bootstrap-argocd CLUSTER=saradomin AGE_KEY_FILE=/path/to/age-key
```

After bootstrap, Argo CD reconciles `clusters/saradomin` from the `main` branch. Until the
change is pushed, use the focused Kustomize render or `make apply CLUSTER=saradomin`.
