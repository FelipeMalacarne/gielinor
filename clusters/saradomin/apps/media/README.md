# Saradomin media and Switch library

The media stack is deployed in the `media` namespace:

- Radarr, Sonarr, Prowlarr, qBittorrent, Bazarr, FlareSolverr
- Jellyfin and Seerr
- Buildarr, which reconciles the Arr API configuration from `buildarr-config.yaml`
- Recyclarr, which synchronizes TRaSH quality definitions, quality profiles, and custom formats
- AeroFoil, serving the Switch library at `aerofoil.saradomin.ftm.dev.br`

Buildarr owns Arr media naming, root folders, qBittorrent download clients, Prowlarr
application links, and the FlareSolverr proxy. Recyclarr owns the managed 1080p and 4K/HDR
quality definitions, profiles, and custom formats. The default profiles target 1080p; separate
2160p/HDR profiles are available for titles selected explicitly. Audio releases are accepted when
they contain the title's original language, Portuguese, or Portuguese (Brazil); Bazarr remains
responsible for Portuguese and English subtitles. After each Recyclarr sync, stock-profile items
are migrated to the managed 1080p profile and Seerr's non-4K request defaults are updated; items
already assigned to the managed 4K profile are preserved. Indexer definitions, Bazarr, Jellyfin,
Seerr, and AeroFoil's library metadata still require their application-specific initial
setup because those projects do not expose a compatible declarative controller here.

The Sonarr, Radarr, and Prowlarr API keys must each be exactly 32 characters because their
Buildarr plugins enforce that length. Generate each key with `openssl rand -hex 16`; a
64-character key from `openssl rand -hex 32` prevents Buildarr from reconciling the stack.

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

## Jellyfin transcoding

Jellyfin receives the Intel render device at `/dev/dri/renderD128` and uses Intel QSV for
hardware decoding, encoding, and HDR tone mapping. Its disposable cache and transcode data
use a 20 GiB `emptyDir` mounted at `/cache`; persistent application state remains on the
`jellyfin-config` PVC.

## qBittorrent peer and Web UI access

qBittorrent uses the fixed peer port `52457` for both TCP and UDP. Kubernetes exposes that
port directly on the Saradomin node. Configure the Deco router to forward TCP and UDP port
`52457` to `10.10.0.10:52457`; the Kubernetes change cannot create this router rule.

The qBittorrent Ingress is protected by Traefik BasicAuth. Its username and generated
password are stored only in the SOPS-encrypted `qbittorrent-webui-auth` Secret. They can be
retrieved locally by decrypting `secrets.yaml`; do not commit `secrets.dec.yaml`. A NetworkPolicy
limits the unauthenticated internal Web UI port to Sonarr, Radarr, and Traefik while leaving only
the TCP/UDP peer port open to arbitrary peers.

## Access

Private services use `*.saradomin.ftm.dev.br` as their canonical names. AdGuard Home
returns the Saradomin LAN address to home clients and the Tailscale-backed
Traefik address to tailnet clients:

- `radarr.saradomin.ftm.dev.br`, `sonarr.saradomin.ftm.dev.br`
- `prowlarr.saradomin.ftm.dev.br`, `bazarr.saradomin.ftm.dev.br`
- `qbit.saradomin.ftm.dev.br`, `jellyfin.saradomin.ftm.dev.br`
- `seerr.saradomin.ftm.dev.br`, `aerofoil.saradomin.ftm.dev.br`
- `argocd.saradomin.ftm.dev.br`, `openclaw.saradomin.ftm.dev.br`

The previous `*.saradomin` names remain as compatibility aliases.

The AeroFoil workload also has a direct LAN `LoadBalancer` on port `8465`. Reserve a stable
DHCP lease for the Saradomin node and configure CyberFoil with
`http://<saradomin-lan-ip>:8465`; this keeps Switch traffic on the LAN and avoids both
Tailscale and the Cloudflare tunnel. If the K3s ServiceLB is disabled, use the explicit
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
