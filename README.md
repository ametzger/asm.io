# asm.io

terraform infrastructure and content for [asm.io](https://asm.io).

## Setup

* Install dependencies: `brew install tfenv just direnv awscli s3cmd python3 jq`
* Install terraform: `cd infra && tfenv install`
* Set up env vars: `cp .envrc.example .envrc` and fill in the env vars, then `direnv allow`
* Set up terraform backend: `cp infra/backend.tf.example infra/backend.tf` and fill in the details
* Bootstrap the infra:
  ```
  cd infra
  terraform init
  terraform apply
  ```
* Deploy the site: `just deploy`

## Development

Use `just serve` to start a local version of the site at http://localhost:8080
