# compute-engine

**One or more GCP Compute Engine VMs**, defined as a map (`instances`) and fanned out with
`for_each` — add a key to add a VM. Each VM has **no external IP** by default; access follows the
same model as AWS SSM Session Manager: **OS Login + IAP TCP forwarding**, where you connect through
Google's infrastructure with your own identity and short-lived, IAM-governed keys (no public SSH
port, no key files to manage). The module is **bootstrap-agnostic** — it runs whatever
`startup_script` each VM passes (e.g. a Docker install), but owns no userdata itself.

## What it creates

For each entry in `instances` (keyed by a short name — that key also keys the `instances` **output**; the VM's GCP name is `<environment_name>-<key>`, so a `postiz` key → output `instances["postiz"]` whose `.name` is `dev-postiz`):

- `google_compute_instance` — the VM. No external IP by default; `enable-oslogin = TRUE` so SSH
  access is governed by IAM, not project metadata keys. Labeled with `environment` + `managed_by`
  plus your `global.tags`, sanitized to GCP's label rules (lowercased; chars outside `[a-z0-9_-]`
  become `_`). Runs that entry's `startup_script` on first
  boot (empty string = no bootstrap). **This module is bootstrap-agnostic** — the actual first-boot
  script (e.g. installing Docker) is **userdata owned by the consuming environment**, not baked into
  the module. See "Bootstrap / userdata" below.
- `google_compute_instance_iam_member` — grants **`roles/compute.osLogin`** to each `access_members`
  principal on every VM, letting them log in over SSH.
- `google_iap_tunnel_instance_iam_member` — grants **`roles/iap.tunnelResourceAccessor`** to each
  `access_members` principal on every VM, letting them open an IAP tunnel to it.

IAM grants fan out as **member × VM** (via `setproduct`) on stable keys, so adding a VM or a member
never reindexes existing grants.

Inbound SSH from the IAP range is allowed by the **`network` component's** `allow-iap-ssh` firewall rule,
and outbound internet (for the Docker install) comes from the `network`'s Cloud NAT — so this module
assumes it is attached to a `network` created by that component (or an equivalent network).

## Access model ("SSM-like")

```text
you / CI service account
   │  (identity + IAM: compute.osLogin + iap.tunnelResourceAccessor)
   ▼
IAP  ──tunnel──▶  VM:22   (no external IP; firewall allows only 35.235.240.0/20)
```

Connect with:

```bash
gcloud compute ssh <instance-name> \
  --zone <zone> --tunnel-through-iap
```

Each `instances[<key>].ssh_command` output prints this for you. To grant someone access, add their principal to
`access_members` (e.g. `user:alice@officialdad.com`, `serviceAccount:ci@<project>.iam.gserviceaccount.com`)
and re-apply — no keys to distribute, and access is revoked the moment IAM is removed.

## Bootstrap / userdata

The module does **not** know what to install — it just runs whatever `startup_script` string the
caller passes, on first boot, as the instance's `metadata_startup_script`. Pass `""` (the default)
for a plain VM.

The **consuming environment owns the bootstrap**. In `infra-environments-dev` the Docker install
lives as a script file (`compute-engine/userdata/docker-bootstrap.sh`), read with `file()` and
passed as that VM's `startup_script` inside the `instances` map:

```hcl
inputs = {
  network    = dependency.network.outputs.network_self_link
  subnetwork = dependency.network.outputs.subnetwork_self_link

  instances = {
    dev = {
      machine_type   = "e2-micro"
      network_tags   = [dependency.network.outputs.ssh_tag]
      startup_script = file("${get_terragrunt_dir()}/userdata/docker-bootstrap.sh")
    }
  }
}
```

Leave `startup_script` unset (or `""`) for a plain VM. This keeps the cookbook module generic (any
VM, any bootstrap) and puts the "what runs on boot" decision where environment-specific choices
belong. A Docker bootstrap needs outbound internet (apt + docker.com), which the `network`'s Cloud
NAT provides to these otherwise-private VMs.

## Auth

Provider needs `project_id` + credentials (ADC / `GOOGLE_APPLICATION_CREDENTIALS` / CI service
account); region from `var.global.deploy_region`. The principal running `apply` needs rights to
create instances and set IAM on them, and the **OS Login API**, **Compute API**, and **IAP API**
must be enabled on the project.

## Dependencies

- **Consumes** `network` (`network.network_self_link`) and `subnetwork`
  (`network.subnetwork_self_link`) from the **`network`** component.
- **Relies on** the `network`'s `allow-iap-ssh` firewall rule (inbound SSH from IAP) and Cloud NAT
  (outbound, for the Docker install).

### `instances` entry shape

The generated Inputs table renders `instances` as one `map(object({…}))` with each field's default.
Per-field intent (all optional; each entry overrides only what it sets):

- `machine_type` (`e2-micro`) — machine type.
- `boot_image` (`debian-cloud/debian-12`) — boot image (`project/family` or full self link).
- `boot_disk_size_gb` (`20`) — boot disk size.
- `zone` (`""`) — empty → `"<deploy_region>-a"`.
- `assign_public_ip` (`false`) — leave `false` for the IAP-only model.
- `startup_script` (`""`) — first-boot script; empty = no bootstrap. Supplied by the env.
- `network_tags` (`[]`) — firewall tags (e.g. `[network.ssh_tag]`). Empty = no tag-scoped inbound.

> **Why `project_id` is required and `access_members` defaults to `[]`:** a reusable module should
> know *how* to build a VM, never *where* or *who* — that's environment identity, owned by the call
> site. `project_id` has no safe default (defaulting to one env's project risks another env silently
> provisioning into it), so it's required and fails loudly when unset. `access_members` defaults to
> "no access" (safe when forgotten) rather than a hard-coded person. The cost-safe *how* knobs
> (`e2-micro`, `debian-12`, 20 GB) keep defaults, since a forgotten value there is harmless.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| global | Environment-wide context injected by the environments repo (name, region, tags). | <pre>object({<br/>    environment_name = string<br/>    deploy_region    = string<br/>    tags             = map(string)<br/>  })</pre> | n/a | yes |
| network | Network self link or name (from network.network\_self\_link). Shared by all instances. | `string` | n/a | yes |
| project\_id | GCP project the VMs are created in. Required — set per environment so a forgotten value fails loudly instead of silently landing resources in the wrong project (e.g. prod into dev). | `string` | n/a | yes |
| subnetwork | Subnetwork self link or name (from network.subnetwork\_self\_link). Shared by all instances. | `string` | n/a | yes |
| access\_members | IAM principals (user:/group:/serviceAccount:) granted OS Login + IAP tunnel access on EVERY VM. Empty = no SSH access; each environment opts in its own people. | `list(string)` | `[]` | no |
| instances | VMs to create, keyed by short name. Each entry overrides only the fields it needs; the rest take module defaults. VM name = "<env>-<key>". | <pre>map(object({<br/>    machine_type      = optional(string, "e2-micro")<br/>    boot_image        = optional(string, "debian-cloud/debian-12")<br/>    boot_disk_size_gb = optional(number, 20)<br/>    zone              = optional(string, "")<br/>    assign_public_ip  = optional(bool, false)<br/>    startup_script    = optional(string, "")<br/>    network_tags      = optional(list(string), [])<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| instances | Per-instance details keyed by instance key: name, instance\_id, internal\_ip, zone, and a ready-to-run IAP ssh\_command. |
<!-- END_TF_DOCS -->
