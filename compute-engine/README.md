# compute-engine

A **GCP Compute Engine VM with Docker** installed on first boot. The VM has **no external IP** —
access follows the same model as AWS SSM Session Manager: **OS Login + IAP TCP forwarding**, where
you connect through Google's infrastructure with your own identity and short-lived,
IAM-governed keys (no public SSH port, no key files to manage).

## What it creates

- `google_compute_instance` — the VM. No external IP by default; `enable-oslogin = TRUE` so SSH
  access is governed by IAM, not project metadata keys. Runs the caller-supplied `startup_script`
  on first boot (empty string = no bootstrap). **This module is bootstrap-agnostic** — the actual
  first-boot script (e.g. installing Docker) is **userdata owned by the consuming environment**,
  not baked into the module. See "Bootstrap / userdata" below.
- `google_compute_instance_iam_member` (per member) — grants **`roles/compute.osLogin`** to each
  `access_members` principal, letting them log in over SSH.
- `google_iap_tunnel_instance_iam_member` (per member) — grants **`roles/iap.tunnelResourceAccessor`**
  to each `access_members` principal, letting them open an IAP tunnel to the VM.

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

The `ssh_command` output prints this for you. To grant someone access, add their principal to
`access_members` (e.g. `user:alice@officialdad.com`, `serviceAccount:ci@<project>.iam.gserviceaccount.com`)
and re-apply — no keys to distribute, and access is revoked the moment IAM is removed.

## Bootstrap / userdata

The module does **not** know what to install — it just runs whatever `startup_script` string the
caller passes, on first boot, as the instance's `metadata_startup_script`. Pass `""` (the default)
for a plain VM.

The **consuming environment owns the bootstrap**. In `infra-environments-dev` the Docker install
lives as a script file (e.g. `compute-engine/userdata/docker-bootstrap.sh`) and a switch in the
unit's `terragrunt.hcl` decides whether to pass it:

```hcl
locals {
  install_docker = true
}
inputs = {
  startup_script = local.install_docker ? file("${get_terragrunt_dir()}/userdata/docker-bootstrap.sh") : ""
}
```

This keeps the cookbook module generic (any VM, any bootstrap) and puts the "what runs on boot"
decision where environment-specific choices belong. A Docker bootstrap needs outbound internet
(apt + docker.com), which the `network`'s Cloud NAT provides to this otherwise-private VM.

## Auth

Provider needs `project_id` + credentials (ADC / `GOOGLE_APPLICATION_CREDENTIALS` / CI service
account); region from `var.global.deploy_region`. The principal running `apply` needs rights to
create instances and set IAM on them, and the **OS Login API**, **Compute API**, and **IAP API**
must be enabled on the project.

## Inputs

| Name                | Type         | Default                  | Description                                                              |
| ------------------- | ------------ | ------------------------ | ------------------------------------------------------------------------ |
| `global`            | object       | —                        | Env-wide context (`environment_name`, `deploy_region`, `tags`).          |
| `project_id`        | string       | —                        | GCP project the VM is created in.                                        |
| `network`           | string       | —                        | Network self link / name (from `network.network_self_link`).            |
| `subnetwork`        | string       | —                        | Subnetwork self link / name (from `network.subnetwork_self_link`).      |
| `zone`              | string       | `""`                     | Zone for the VM. Empty → `"<deploy_region>-a"`.                          |
| `machine_type`      | string       | `e2-micro`               | Machine type.                                                            |
| `boot_image`        | string       | `debian-cloud/debian-12` | Boot image (`project/family` or full self link).                         |
| `boot_disk_size_gb` | number       | `20`                     | Boot disk size in GB.                                                    |
| `startup_script`    | string       | `""`                     | First-boot script (userdata). Empty = no bootstrap. Supplied by the env. |
| `assign_public_ip`  | bool         | `false`                  | Attach an ephemeral external IP. Leave `false` for the IAP-only model.   |
| `access_members`    | list(string) | `[]`                     | IAM principals granted OS Login + IAP tunnel access (see access model).  |

## Outputs

| Name            | Description                                                       |
| --------------- | ---------------------------------------------------------------- |
| `instance_name` | The VM name (`<environment_name>-compute-engine`).               |
| `instance_id`   | The instance ID.                                                 |
| `internal_ip`   | The VM's internal IP.                                            |
| `zone`          | The zone the VM runs in.                                         |
| `ssh_command`   | Ready-to-run `gcloud compute ssh ... --tunnel-through-iap` line. |

## Dependencies

Consumes `network` and `subnetwork` from the `network` component. Relies on the `network`'s `allow-iap-ssh`
firewall rule (inbound SSH from IAP) and Cloud NAT (outbound, for the Docker install).
