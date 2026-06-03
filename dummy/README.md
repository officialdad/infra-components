# dummy

A **credential-free** component for testing the CI/CD pipeline end to end (plan → PR comment →
gated apply) with no AWS account. It uses only the `random`, `local`, and `null` providers, so
`terraform plan`/`apply` produce real, meaningful output on a CI runner with zero secrets.

## What it creates

- `random_pet.name` — a random name prefixed with `<env>-dummy`.
- `local_file.artifact` — a small text file under `generated/` describing the environment.
- `null_resource.marker` — a trigger that changes with the pet name (demonstrates replacement).

## Inputs

| Name         | Type   | Default                          | Description                       |
| ------------ | ------ | -------------------------------- | --------------------------------- |
| `global`     | object | —                                | Env-wide context.                 |
| `pet_length` | number | `2`                              | Words in the generated pet name.  |
| `message`    | string | `hello from the dummy component` | Message written into the artifact. |

## Outputs

| Name            | Description                       |
| --------------- | --------------------------------- |
| `pet_name`      | The generated pet name.           |
| `artifact_path` | Path of the generated local file. |

## Why it exists

It lets you validate the whole pipeline — git-sourced module fetch, Terragrunt wiring, plan
summary posted to the PR, and the gated apply-on-merge — before wiring real AWS credentials.
Once the pipeline is proven, you can remove this component (and its leaves in the env repos).
