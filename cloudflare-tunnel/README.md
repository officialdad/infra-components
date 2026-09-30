# cloudflare-tunnel

Ingress routes, DNS and optional Access protection for **one existing Cloudflare tunnel** — the tunnel
is created by hand, this component only manages what it routes, the records that point at it, and who
may reach it.

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
  the only TTL Cloudflare accepts on a proxied record). Each record waits for its hostname's Access
  application, so nothing resolves unprotected.
- **`cloudflare_zero_trust_access_application`** — one `self_hosted` app per **distinct** hostname
  whose route has an `access` block. Absent for routes without one.
- **`cloudflare_zero_trust_access_policy`** — one `allow` policy per protected hostname, built from
  `emails` and `email_domains`. Absent when the block passes only `policy_ids`.

The catch-all `{ service = "http_status:404" }` rule is **appended by the module**. Cloudflare
rejects a config whose last rule is hostname-scoped, so callers never have to remember it — do not
put it in `routes`.

### What it deliberately does not create

- **The tunnel itself (`cloudflare_zero_trust_tunnel_cloudflared`).** That resource carries
  `tunnel_secret`, which Terraform writes to state **in plaintext**. The tunnel and its token are
  created by hand; the token lives in AWS SSM as a `SecureString`. The tunnel **id** is not a secret
  and comes in as the plain `tunnel_id` input.
- **Access groups, MFA, service tokens, per-route origin timeouts, WARP routing.** Add them when a
  consumer needs them.
- **The identity provider.** Registering Google (or any provider) in Zero Trust is a human step.
  The module only references provider ids you pass.

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

## Access

Add an `access` object to a route to put its hostname behind Cloudflare Access. One apply creates the
application, its allow policy, and the `cloudflared` JWT check, and a renamed hostname carries all
three with it. Routes with no `access` block plan exactly as before.

```hcl
access_team_name = "example-team"

routes = [
  {
    hostname = "admin.example.com"
    service  = "http://localhost:3001"
    access = {
      emails       = ["staff@example.com"]
      allowed_idps = ["example-idp-id"]
    }
  },
]
```

`access` entry shape:

- `emails` — addresses admitted by the allow policy, one `email` rule each.
- `email_domains` — domains admitted by the allow policy, one `email_domain` rule each.
- `policy_ids` — existing Access policy ids attached after the module's own policy.
- `allowed_idps` — identity provider ids the app offers at login. One entry also skips the login
  method picker. `null` keeps every login method on the account, so the allow list alone gates the app.

This module holds no email address and no identity provider id. The consumer passes both. Check each
`allowed_idps` id in the Zero Trust dashboard first, because a wrong id locks every user out.

`access_team_name` is required once any route has an `access` block. It is the subdomain of
`<team>.cloudflareaccess.com`. `cloudflared` uses it and the app's `aud` tag to refuse any request
without a valid Access JWT (`required = true`). A wrong team name makes `cloudflared` reject every
request, so the hostname goes dark.

Rules the module enforces at plan time:

- An `access` block names at least one of `emails`, `email_domains` or `policy_ids`.
- Values are non-empty and hold no `*`, so an allow list can never become an everyone rule.
- `allowed_idps` is `null` or a non-empty list of non-empty strings.
- Every route on one hostname carries the same `access` object. Access protects a hostname, not a
  path.

> ⚠️ **Adoption trap: hand-made Access apps.** The module creates its own app for each protected
> hostname. If a hand-made app already covers that hostname, the first apply makes a second app on the
> same hostname. Its behaviour is unconfirmed until tested in a dev environment. Import the hand-made
> app into state first. One app that covers several hostnames (for example a dev and a prod
> hostname) must be split into one app per hostname before either environment imports it. Otherwise
> the first apply strips the other hostname and leaves it unprotected.
>
> ⚠️ **The token needs a new scope.** Access resources need **Access: Apps and Policies Edit** on
> the account. Without it the plan is green, because every new resource is a create, and the apply
> fails part-way. `access` is `null` by default, so a consumer that only bumps the tag plans no
> change and needs no new scope.
>
> ⚠️ **Rolling back.** Hand-make the replacement Access app first. Then pin back to the previous tag.
> The pin-back apply removes the Terraform-managed app, so the hostname must never be unprotected in
> between.

## Auth

The provider reads `CLOUDFLARE_API_TOKEN` from the environment. **No token is stored in this module
or in git.** Use a scoped API **token**, not the global API key (the global key is account-wide and
cannot be narrowed).

Minimum scopes:

| Scope | Permission | Resource |
| ----- | ---------- | -------- |
| Account | Cloudflare Tunnel | Edit — on the account in `account_id` |
| Zone | DNS | Edit — on the target zone only, not "All zones" |
| Account | Access: Apps and Policies | Edit — only when a route has an `access` block |

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
- `access` — optional. Protects the hostname with Cloudflare Access. See [Access](#access).

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| account\_id | Cloudflare account id that owns the tunnel. | `string` | n/a | yes |
| routes | Ingress rules for the tunnel, in match order. Cloudflare takes the first match, so a path-scoped rule must come before the unscoped rule for the same hostname, or the unscoped rule swallows every request. The path field is a regex evaluated by cloudflared and is passed through untouched. The trailing catch-all rule is appended by the module — do not include it here. The optional access object puts the route's hostname behind Cloudflare Access: emails and email\_domains become one allow policy, policy\_ids are existing policies attached alongside it, and allowed\_idps (identity provider ids) limits the login methods, defaulting to every method on the account when null. Every route on one hostname must carry the same access object, because Access protects a hostname, not a path. Needs access\_team\_name. | <pre>list(object({<br/>    hostname = string<br/>    service  = string<br/>    path     = optional(string)<br/>    access = optional(object({<br/>      emails        = optional(list(string), [])<br/>      email_domains = optional(list(string), [])<br/>      policy_ids    = optional(list(string), [])<br/>      allowed_idps  = optional(list(string))<br/>    }))<br/>  }))</pre> | n/a | yes |
| tunnel\_id | Id of the already-created tunnel this component configures. Not a secret — the tunnel and its token are created out-of-band (see README). | `string` | n/a | yes |
| zone\_id | Cloudflare zone id the route hostnames live in. Every hostname in routes must belong to this zone. | `string` | n/a | yes |
| access\_team\_name | Zero Trust team name, the subdomain of <team>.cloudflareaccess.com. cloudflared uses it to check the Access JWT on every protected route, so it is required as soon as any route has an access block. A wrong value makes cloudflared reject every request. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| access\_application\_ids | Map of hostname -> Access application id, for the hostnames whose route has an access block. Empty when no route is protected. |
| access\_aud\_tags | Map of hostname -> Access application audience tag, the value cloudflared checks in the Access JWT. Empty when no route is protected. |
| dns\_record\_ids | Map of hostname -> Cloudflare DNS record id. These are the ids the import procedure needs. |
| hostnames | Distinct hostnames routed through the tunnel, one CNAME each. |
| tunnel\_id | Id of the tunnel this component configures. |
<!-- END_TF_DOCS -->
