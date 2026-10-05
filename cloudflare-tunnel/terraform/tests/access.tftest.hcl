# Runs against a mocked provider: no credentials, no API call. Every value below is a placeholder.

mock_provider "cloudflare" {}

variables {
  account_id = "example-account-id"
  zone_id    = "example-zone-id"
  tunnel_id  = "example-tunnel-id"
}

run "no_access_block_creates_no_access_resources" {
  command = plan

  variables {
    routes = [
      { hostname = "app.example.com", service = "http://localhost:3000", path = "^/api" },
      { hostname = "app.example.com", service = "http://localhost:3000" },
    ]
  }

  assert {
    condition     = length(cloudflare_zero_trust_access_application.this) == 0
    error_message = "A route without access must not create an Access application."
  }

  assert {
    condition     = length(cloudflare_zero_trust_access_policy.this) == 0
    error_message = "A route without access must not create an Access policy."
  }

  # The ingress list is exactly what the module produced before access existed: no origin_request
  # on a route, and the catch-all last.
  assert {
    condition = jsonencode(cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress) == jsonencode([
      { hostname = "app.example.com", service = "http://localhost:3000", path = "^/api", origin_request = null },
      { hostname = "app.example.com", service = "http://localhost:3000", path = null, origin_request = null },
      { hostname = null, service = "http_status:404", path = null, origin_request = null },
    ])
    error_message = "Unprotected routes must keep the ingress list they had before access existed."
  }

  assert {
    condition     = output.access_application_ids == {} && output.access_aud_tags == {}
    error_message = "Access outputs must be empty when no route is protected."
  }
}

run "access_route_creates_one_application_and_one_policy" {
  command = apply

  variables {
    access_team_name = "example-team"
    routes = [
      {
        hostname = "admin.example.com"
        service  = "http://localhost:3001"
        path     = "^/api"
        access = {
          emails       = ["staff@example.com"]
          allowed_idps = ["example-idp-id"]
        }
      },
      {
        hostname = "admin.example.com"
        service  = "http://localhost:3001"
        access = {
          emails       = ["staff@example.com"]
          allowed_idps = ["example-idp-id"]
        }
      },
      { hostname = "open.example.com", service = "http://localhost:3002" },
    ]
  }

  assert {
    condition     = length(cloudflare_zero_trust_access_application.this) == 1
    error_message = "Two routes on one protected hostname must share one Access application."
  }

  assert {
    condition     = length(cloudflare_zero_trust_access_policy.this) == 1
    error_message = "A protected hostname with emails must get one allow policy."
  }

  assert {
    condition     = cloudflare_zero_trust_access_application.this["admin.example.com"].type == "self_hosted"
    error_message = "The Access application must be self_hosted."
  }

  assert {
    condition     = cloudflare_zero_trust_access_application.this["admin.example.com"].allowed_idps == toset(["example-idp-id"])
    error_message = "allowed_idps must reach the Access application unchanged."
  }

  assert {
    condition     = cloudflare_zero_trust_access_application.this["admin.example.com"].auto_redirect_to_identity == true
    error_message = "A single allowed identity provider must skip the login method picker."
  }

  assert {
    condition     = cloudflare_zero_trust_access_policy.this["admin.example.com"].decision == "allow"
    error_message = "The policy must be an allow policy."
  }

  assert {
    condition     = length([for r in cloudflare_zero_trust_access_policy.this["admin.example.com"].include : r if r.email != null]) == 1
    error_message = "emails = [one address] must yield exactly one email rule."
  }

  assert {
    condition     = length([for r in cloudflare_zero_trust_access_policy.this["admin.example.com"].include : r if r.email_domain != null]) == 0
    error_message = "With no email_domains the policy must hold no email_domain rule."
  }

  assert {
    condition     = length(cloudflare_zero_trust_access_application.this["admin.example.com"].policies) == 1
    error_message = "The application must reference the policy the module created."
  }

  assert {
    condition = alltrue([
      for i in slice(cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress, 0, 2) :
      i.origin_request.access.required == true
      && i.origin_request.access.team_name == "example-team"
      && jsonencode(i.origin_request.access.aud_tag) == jsonencode([cloudflare_zero_trust_access_application.this["admin.example.com"].aud])
    ])
    error_message = "Every protected ingress rule must require Access and carry the team name and the application's aud tag."
  }

  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress[2].origin_request == null
    error_message = "An unprotected hostname next to a protected one must keep no origin_request."
  }

  assert {
    condition     = output.access_aud_tags["admin.example.com"] == cloudflare_zero_trust_access_application.this["admin.example.com"].aud
    error_message = "access_aud_tags must expose the application's aud tag."
  }
}

run "policy_ids_only_attaches_existing_policies" {
  command = plan

  variables {
    access_team_name = "example-team"
    routes = [
      { hostname = "admin.example.com", service = "http://localhost:3001", access = { policy_ids = ["example-policy-id"] } },
    ]
  }

  assert {
    condition     = length(cloudflare_zero_trust_access_policy.this) == 0
    error_message = "policy_ids alone must not create a policy."
  }

  assert {
    condition     = [for p in cloudflare_zero_trust_access_application.this["admin.example.com"].policies : p.id] == ["example-policy-id"]
    error_message = "The application must reference the consumer's policy id."
  }

  assert {
    condition     = cloudflare_zero_trust_access_application.this["admin.example.com"].allowed_idps == null
    error_message = "A null allowed_idps must keep the account's login methods."
  }
}

run "empty_allowed_idps_is_rejected" {
  command = plan

  variables {
    access_team_name = "example-team"
    routes = [
      { hostname = "admin.example.com", service = "http://localhost:3001", access = { emails = ["staff@example.com"], allowed_idps = [] } },
    ]
  }

  expect_failures = [var.routes]
}

run "access_without_any_rule_is_rejected" {
  command = plan

  variables {
    access_team_name = "example-team"
    routes = [
      { hostname = "admin.example.com", service = "http://localhost:3001", access = {} },
    ]
  }

  expect_failures = [var.routes]
}

run "wildcard_email_is_rejected" {
  command = plan

  variables {
    access_team_name = "example-team"
    routes = [
      { hostname = "admin.example.com", service = "http://localhost:3001", access = { email_domains = ["*"] } },
    ]
  }

  expect_failures = [var.routes]
}

run "half_protected_hostname_is_rejected" {
  command = plan

  variables {
    access_team_name = "example-team"
    routes = [
      { hostname = "admin.example.com", service = "http://localhost:3001", path = "^/api" },
      { hostname = "admin.example.com", service = "http://localhost:3001", access = { emails = ["staff@example.com"] } },
    ]
  }

  expect_failures = [var.routes]
}

run "access_without_team_name_is_rejected" {
  command = plan

  variables {
    routes = [
      { hostname = "admin.example.com", service = "http://localhost:3001", access = { emails = ["staff@example.com"] } },
    ]
  }

  expect_failures = [cloudflare_zero_trust_tunnel_cloudflared_config.this]
}
