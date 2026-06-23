# network

Network foundation component (**GCP**): a custom-mode VPC network with one **regional**
subnetwork, **Private Google Access**, optional **Cloud NAT** for private-instance egress, and a
baseline firewall (intra-network traffic + IAP SSH).

This component is a **thin wrapper** over two verified Google Cloud Foundation Toolkit modules —
it manages no raw `google_compute_*` resources itself. It bakes in *our* opinions (the IAP-SSH
rule, the `ssh_tag` contract, naming, the `global` convention) so the environments repos consume a
small, stable interface and never see the upstream modules' full input surface.

| Wraps | Version | Provides |
| ----- | ------- | -------- |
| [`terraform-google-modules/network/google`](https://registry.terraform.io/modules/terraform-google-modules/network/google) | `~> 18.0` | network + regional subnet + firewall rules |
| [`terraform-google-modules/cloud-router/google`](https://registry.terraform.io/modules/terraform-google-modules/cloud-router/google) | `~> 9.0` | Cloud Router + NAT (only when `enable_cloud_nat`) |

GCP networking differs from AWS in ways that make this component simpler:

- A subnetwork is **regional** (every zone in the region shares it), so one subnetwork covers the
  whole region — no per-AZ subnet fan-out, no route tables to associate.
- There is **no "public subnet."** Whether an instance is reachable from the internet depends on
  whether it has an external IP, not on the subnet. This component keeps instances **private** and
  provides egress via Cloud NAT plus inbound SSH via IAP (see the `compute-engine` component).

## What it creates

- A **custom-mode VPC network** (`auto_create_subnetworks = false`) with REGIONAL routing.
- One **regional subnetwork** (`subnet_cidr`) with `private_ip_google_access` on, so instances can
  reach Google APIs without an external IP.
- **Cloud Router + NAT** — only when `enable_cloud_nat` (default `true`). Outbound internet for
  instances with no external IP (e.g. so a VM's bootstrap can `apt-get install docker`). This is the
  one piece that costs money at idle (~\$1/day) — set `enable_cloud_nat = false` to stop charges.
- Firewall **`allow-internal`** — intra-network traffic (tcp/udp/icmp) from `subnet_cidr`.
- Firewall **`allow-iap-ssh`** — only when `enable_iap_ssh` (default `true`). Allows tcp:22 from
  Google's IAP range `35.235.240.0/20`, **scoped via `target_tags` to VMs wearing the exported
  `ssh_tag`** — so only opted-in instances accept SSH. `gcloud compute ssh --tunnel-through-iap`
  then works without exposing SSH to the internet.

Firewall rules are passed to the network module as `ingress_rules` **data**, not declared as
separate `google_compute_firewall` resources — the module renders them.

## Auth

The provider needs a GCP **project** and credentials. Set the project via `project_id`; supply
credentials out-of-band (Application Default Credentials, `GOOGLE_APPLICATION_CREDENTIALS`, or a
service account in CI). No key is stored in this component. Region comes from
`var.global.deploy_region`.

## A note on tags vs. labels

The repo convention is to tag every resource with `Environment` / `ManagedBy`. GCP **networking**
resources (network, subnetwork, router, firewall) **don't support labels**, so the convention is
only honored where the provider allows it (e.g. the instance in `compute-engine`). Naming still
follows `<environment_name>-network[-purpose]`.

## Inputs

| Name              | Type   | Default        | Description                                                        |
| ----------------- | ------ | -------------- | ------------------------------------------------------------------ |
| `global`          | object | —              | Env-wide context (`environment_name`, `deploy_region`, `tags`).    |
| `project_id`      | string | —              | GCP project the network is created in.                             |
| `subnet_cidr`     | string | `10.0.0.0/16`  | Primary IPv4 range of the regional subnetwork.                     |
| `enable_cloud_nat`| bool   | `true`         | Create Cloud Router + NAT for egress from private instances.       |
| `enable_iap_ssh`  | bool   | `true`         | Add a firewall rule allowing IAP (`35.235.240.0/20`) on tcp:22.    |

## Outputs

| Name                   | Description                                                  |
| ---------------------- | ------------------------------------------------------------ |
| `network_name`         | The VPC network name.                                        |
| `network_self_link`    | The network self link (pass to `compute-engine.network`).    |
| `subnetwork_name`      | The regional subnetwork name.                                |
| `subnetwork_self_link` | The subnetwork self link (pass to `compute-engine.subnetwork`). |
| `region`               | The region the subnetwork lives in.                          |
| `ssh_tag`              | Network tag granting IAP SSH; pass into a VM's `network_tags`. |

Consumed by `compute-engine` (`network_self_link` → `network`, `subnetwork_self_link` →
`subnetwork`, `ssh_tag` → one of `network_tags`).
