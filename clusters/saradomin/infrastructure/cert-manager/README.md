# Saradomin certificates

cert-manager issues a public wildcard certificate for
`*.saradomin.ftm.dev.br` through a Cloudflare DNS-01 challenge. The internal
services remain private; only temporary `_acme-challenge` TXT records are
published.

## Cloudflare token

Create a token restricted to the `ftm.dev.br` zone with:

- `Zone / DNS / Edit`
- `Zone / Zone / Read`

The ignored `secrets.dec.yaml` file beside this README contains a placeholder.
Replace only the `api-token` value, then encrypt this one secret safely:

```sh
cd clusters/saradomin/infrastructure/cert-manager
tmp=$(mktemp ./secrets.yaml.XXXXXX)
sops --encrypt secrets.dec.yaml > "$tmp" && mv "$tmp" secrets.yaml
```

Never commit `secrets.dec.yaml`. Confirm that only the encrypted `secrets.yaml`
is staged.

## Certificate flow

The cert-manager Helm release installs its CRDs and these extra objects:

- staging and production Cloudflare `ClusterIssuer` resources;
- a production `Certificate` that writes `saradomin-wildcard-tls` in the
  `networking` namespace;
- Traefik's cluster-wide `default` `TLSStore`, backed by that Secret.

The previous `*.saradomin` compatibility names are not covered by a public
certificate. Use the canonical `*.saradomin.ftm.dev.br` names for trusted HTTPS.
