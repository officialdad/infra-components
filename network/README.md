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

## Dependencies

- **Upstream:** none — `network` is a GCP network foundation.
- **Consumed by `compute-engine`:** `network_self_link` → `network`, `subnetwork_self_link` →
  `subnetwork`, `ssh_tag` → one of `network_tags`.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| global | Environment-wide context injected by the environments repo (name, region, tags). | <pre>object({<br/>    environment_name = string<br/>    deploy_region    = string<br/>    tags             = map(string)<br/>  })</pre> | n/a | yes |
| project\_id | GCP project the network is created in. | `string` | n/a | yes |
| enable\_cloud\_nat | Create Cloud Router + NAT so instances with no external IP get egress. | `bool` | `true` | no |
| enable\_iap\_ssh | Allow SSH (tcp:22) from Google's IAP range so --tunnel-through-iap works. | `bool` | `true` | no |
| subnet\_cidr | Primary IPv4 range of the regional subnetwork. | `string` | `"10.0.0.0/16"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| network\_name | The VPC network name. |
| network\_self\_link | Network self link (pass to compute-engine.network). |
| region | Region the subnetwork lives in. |
| ssh\_tag | Network tag that grants IAP SSH. Pass into a VM's network\_tags to let it accept SSH (e.g. network\_tags = [module.network.ssh\_tag]). |
| subnetwork\_name | The regional subnetwork name. |
| subnetwork\_self\_link | Subnetwork self link (pass to compute-engine.subnetwork). |
<!-- END_TF_DOCS -->
