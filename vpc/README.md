# vpc

Network foundation component (**GCP**): a custom-mode VPC network with one **regional**
subnetwork, **Private Google Access**, optional **Cloud NAT** for private-instance egress, and
baseline firewall rules. Written fresh for GCP — it shares nothing with the old AWS module of the
same name.

GCP networking differs from AWS in ways that make this module simpler:

- A subnetwork is **regional** (every zone in the region shares it), so one subnetwork covers the
  whole region — no per-AZ subnet fan-out, no route tables to associate.
- There is **no "public subnet."** Whether an instance is reachable from the internet depends on
  whether it has an external IP, not on the subnet. This module keeps instances **private** and
  provides egress via Cloud NAT plus inbound SSH via IAP (see the `compute-engine` component).

## What it creates

- `google_compute_network` — custom-mode VPC (`auto_create_subnetworks = false`), regional routing.
- `google_compute_subnetwork` — one subnet (`subnet_cidr`) with `private_ip_google_access = true`
  so instances can reach Google APIs without an external IP.
- `google_compute_router` + `google_compute_router_nat` — **only when `enable_cloud_nat`** (default
  `true`). Outbound internet for instances with no external IP (e.g. so a VM's bootstrap can
  `apt-get install docker`). This is the one piece that costs money at idle (~\$1/day) — destroy it
  to stop charges.
- `google_compute_firewall` `allow-internal` — intra-VPC traffic (tcp/udp/icmp) from `subnet_cidr`.
- `google_compute_firewall` `allow-iap-ssh` — **only when `enable_iap_ssh`** (default `true`). Allows
  tcp:22 from Google's IAP range `35.235.240.0/20`, so `gcloud compute ssh --tunnel-through-iap`
  works without exposing SSH to the internet.

## Auth

The provider needs a GCP **project** and credentials. Set the project via `project_id`; supply
credentials out-of-band (Application Default Credentials, `GOOGLE_APPLICATION_CREDENTIALS`, or a
service account in CI). No key is stored in this module. Region comes from
`var.global.deploy_region`.

## A note on tags vs. labels

The repo convention is to tag every resource with `Environment` / `ManagedBy`. GCP **networking**
resources (network, subnetwork, router, firewall) **don't support labels**, so the convention is
only honored where the provider allows it (e.g. the instance in `compute-engine`). Naming still
follows `<environment_name>-vpc[-purpose]`.

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

Consumed by `compute-engine` (`network_self_link` → `network`, `subnetwork_self_link` → `subnetwork`).
