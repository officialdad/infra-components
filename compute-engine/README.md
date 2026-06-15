# compute-engine

**One or more GCP Compute Engine VMs**, defined as a map (`instances`) and fanned out with
`for_each` — add a key to add a VM. Each VM has **no external IP** by default; access follows the
same model as AWS SSM Session Manager: **OS Login + IAP TCP forwarding**, where you connect through
Google's infrastructure with your own identity and short-lived, IAM-governed keys (no public SSH
port, no key files to manage). The module is **bootstrap-agnostic** — it runs whatever
`startup_script` each VM passes (e.g. a Docker install), but owns no userdata itself.

## What it creates

For each entry in `instances` (keyed by short name; VM name = `<environment_name>-compute-engine-<key>`):

- `google_compute_instance` — the VM. No external IP by default; `enable-oslogin = TRUE` so SSH
  access is governed by IAM, not project metadata keys. Runs that entry's `startup_script` on first
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

```
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

## Inputs

| Name             | Type         | Default | Description                                                                                       |
| ---------------- | ------------ | ------- | ------------------------------------------------------------------------------------------------ |
| `global`         | object       | —       | Env-wide context (`environment_name`, `deploy_region`, `tags`).                                  |
| `project_id`     | string       | —       | **Required.** GCP project the VMs are created in. Set per environment (see note below).          |
| `network`        | string       | —       | Network self link / name (from `network.network_self_link`). Shared by all VMs.                  |
| `subnetwork`     | string       | —       | Subnetwork self link / name (from `network.subnetwork_self_link`). Shared by all VMs.            |
| `access_members` | list(string) | `[]`    | IAM principals granted OS Login + IAP access on **every** VM. Empty = no SSH access (see note).  |
| `instances`      | map(object)  | `{}`    | VMs to create, keyed by short name. Per-VM fields below; each entry overrides only what it needs. |

Per-VM fields inside each `instances` entry (all optional):

| Field               | Default                  | Description                                                              |
| ------------------- | ------------------------ | ----------------------------------------------------------------------- |
| `machine_type`      | `e2-micro`               | Machine type.                                                            |
| `boot_image`        | `debian-cloud/debian-12` | Boot image (`project/family` or full self link).                        |
| `boot_disk_size_gb` | `20`                     | Boot disk size in GB.                                                    |
| `zone`              | `""`                     | Zone. Empty → `"<deploy_region>-a"`.                                     |
| `assign_public_ip`  | `false`                  | Attach an ephemeral external IP. Leave `false` for the IAP-only model.   |
| `startup_script`    | `""`                     | First-boot script (userdata). Empty = no bootstrap. Supplied by the env. |
| `network_tags`      | `[]`                     | Firewall tags (e.g. `[network.ssh_tag]`). Empty = no tag-scoped inbound. |

> **Why `project_id` is required and `access_members` defaults to `[]`:** a reusable module should
> know *how* to build a VM, never *where* or *who* — that's environment identity, owned by the call
> site. `project_id` has no safe default (defaulting to one env's project risks another env silently
> provisioning into it), so it's required and fails loudly when unset. `access_members` defaults to
> "no access" (safe when forgotten) rather than a hard-coded person. The cost-safe *how* knobs
> (`e2-micro`, `debian-12`, 20 GB) keep defaults, since a forgotten value there is harmless.

## Outputs

| Name        | Type        | Description                                                                                                                                                                |
| ----------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `instances` | map(object) | Per-VM details keyed by instance key. Each value has `name`, `instance_id`, `internal_ip`, `zone`, and a ready-to-run `ssh_command` (`gcloud compute ssh … --tunnel-through-iap`). |

## Dependencies

Consumes `network` and `subnetwork` from the `network` component. Relies on the `network`'s `allow-iap-ssh`
firewall rule (inbound SSH from IAP) and Cloud NAT (outbound, for the Docker install).
