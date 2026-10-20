# -*- just -*-

help:
	@just --list

serve:
	cd site && python -m http.server 8080

invalidate:
  #!/usr/bin/env bash
  set -euxo pipefail
  cd infra
  distribution_id="$(terraform show -json | jq -r '.values.root_module.resources[] | select(.address == "aws_cloudfront_distribution.main") | .values.id')"
  echo "invalidating distribution ${distribution_id}"
  aws cloudfront create-invalidation --distribution-id=${distribution_id} --paths /\* >/dev/null 2>&1

sync:
	cd site && aws s3 sync . s3://${TF_VAR_site_url} --cache-control "public, max-age=300, s-maxage=31536000"

deploy: sync invalidate

update:
    nix flake update
