# cloudflare-tunnel

Ingress routes and DNS for **one existing Cloudflare tunnel** — the tunnel is created by hand, this
component only manages what it routes and the records that point at it.

The `wa-support` stack has no inbound path: everything public arrives through a `cloudflared` tunnel.
The ingress list and its CNAMEs used to be dashboard-clicked, so they drifted without a commit. This
component puts both under IaC.

This component **needs a credential** (a `CLOUDFLARE_API_TOKEN`), so it cannot run on the
credential-free `TG_BACKEND=local` path.

> **Exception to the `global` convention:** like `github`, `cloudflare-tunnel` takes **no `global`
> object**. Cloudflare tunnels, zones and DNS records are account/zone-scoped, not
> environment-scoped, and none of these resources is taggable — a `global` input would be a dead
> declaration (which `tflint`'s recommended preset flags). See
> [README.md](../README.md#the-global-object).

## What it creates

- **`cloudflare_zero_trust_tunnel_cloudflared_config`** — the remotely-managed ingress rule list for
  the tunnel named by `tunnel_id`. One rule per `routes` entry, in list order.
- **`cloudflare_dns_record`** — one proxied `CNAME` per **distinct** hostname in `routes`, pointing
  at `<tunnel_id>.cfargotunnel.com` with `proxied = true` and `ttl = 1` (`1` means automatic and is
  the only TTL Cloudflare accepts on a proxied record).

The catch-all `{ service = "http_status:404" }` rule is **appended by the module**. Cloudflare
rejects a config whose last rule is hostname-scoped, so callers never have to remember it — do not
put it in `routes`.

### What it deliberately does not create

- **The tunnel itself (`cloudflare_zero_trust_tunnel_cloudflared`).** That resource carries
  `tunnel_secret`, which Terraform writes to state **in plaintext**. The tunnel and its token are
  created by hand; the token lives in AWS SSM as a `SecureString`. The tunnel **id** is not a secret
  and comes in as the plain `tunnel_id` input.
- **Access policies, per-route origin timeouts, WARP routing.** Add them when a consumer needs them.

> ⚠️ **`config_src` must be `cloudflare`.** This resource writes the *remotely-managed* config. A
> tunnel set to **locally-managed** ignores it **silently** — no error, no plan diff, no effect, and
> the apply reports success. Check this once before trusting a first apply. A tunnel run from a
> `TUNNEL_TOKEN` (which is how the `wa-support` box runs it) is remotely-managed.
>
> ⚠️ **Terraform wins after adoption.** Once this component is applied, a dashboard edit to the
> ingress list is **reverted on the next apply with no warning**. Route changes become a PR.

### Route order matters

Cloudflare evaluates `routes` top-down and takes the **first match**. A path-scoped rule must come
**before** the unscoped rule for the same hostname, or the unscoped rule swallows every request and
the path rule is dead:

```hcl
routes = [
  # path-scoped FIRST
  { hostname = "chat.example.com", service = "http://localhost:3001", path = "^/api/v1/webhook" },
  # unscoped catch-all for the same hostname
  { hostname = "chat.example.com", service = "http://localhost:3000" },
  { hostname = "waha.example.com", service = "http://localhost:3002" },
]
```

`path` is a **regex** evaluated by `cloudflared` and is passed through untouched — no escaping,
anchoring or normalisation is done for you. The three routes above produce **two** CNAMEs, not
three: records are grouped by distinct hostname.

## Auth

The provider reads `CLOUDFLARE_API_TOKEN` from the environment. **No token is stored in this module
or in git.** Use a scoped API **token**, not the global API key (the global key is account-wide and
cannot be narrowed).

Minimum scopes:

| Scope | Permission | Resource |
| ----- | ---------- | -------- |
| Account | Cloudflare Tunnel | Edit — on the account in `account_id` |
| Zone | DNS | Edit — on the target zone only, not "All zones" |

```bash
export CLOUDFLARE_API_TOKEN=...
```

`account_id` and `zone_id` are inputs, so the provider block needs no configuration beyond the token.

## Dependencies

None — `cloudflare-tunnel` consumes no other component's outputs. `tunnel_id`, `account_id` and
`zone_id` are read off the tunnel and zone that already exist.

## Adopting an existing hand-made tunnel

The config and the records already exist in Cloudflare, so import them or the first apply fights
what's live. Import the config with `<account_id>/<tunnel_id>`:

```bash
terraform import cloudflare_zero_trust_tunnel_cloudflared_config.this "<account_id>/<tunnel_id>"
```

Import each DNS record with `<zone_id>/<dns_record_id>`, keyed by hostname:

```bash
terraform import 'cloudflare_dns_record.this["chat.example.com"]' "<zone_id>/<dns_record_id>"
```

Record ids are not in the dashboard UI — list them:

```bash
curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/<zone_id>/dns_records"
```

Then `terraform plan` and confirm it is **empty** before applying. A non-empty plan after import
means `routes` does not yet match what is live — fix `routes`, not the dashboard.

### `routes` entry shape

The generated Inputs table renders `routes` as one `list(object({…}))`. Per entry:

- `hostname` — the public FQDN. Must belong to the zone in `zone_id`. Repeated across entries is
  fine and yields a single CNAME.
- `service` — where `cloudflared` forwards a match, e.g. `http://localhost:3000`.
- `path` — optional regex on the request path. Omit for a catch-all rule on that hostname.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| account\_id | Cloudflare account id that owns the tunnel. | `string` | n/a | yes |
| routes | Ingress rules for the tunnel, in match order. Cloudflare takes the first match, so a path-scoped rule must come before the unscoped rule for the same hostname, or the unscoped rule swallows every request. The path field is a regex evaluated by cloudflared and is passed through untouched. The trailing catch-all rule is appended by the module — do not include it here. | <pre>list(object({<br/>    hostname = string<br/>    service  = string<br/>    path     = optional(string)<br/>  }))</pre> | n/a | yes |
| tunnel\_id | Id of the already-created tunnel this component configures. Not a secret — the tunnel and its token are created out-of-band (see README). | `string` | n/a | yes |
| zone\_id | Cloudflare zone id the route hostnames live in. Every hostname in routes must belong to this zone. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| dns\_record\_ids | Map of hostname -> Cloudflare DNS record id. These are the ids the import procedure needs. |
| hostnames | Distinct hostnames routed through the tunnel, one CNAME each. |
| tunnel\_id | Id of the tunnel this component configures. |
<!-- END_TF_DOCS -->
