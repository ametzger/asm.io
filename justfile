# -*- just -*-

help:
	just --list

serve:
	cd site && python -m http.server 8080

distribution_id := `cd infra && terraform show -json | jq -r '.values.root_module.resources[] | select(.address == "aws_cloudfront_distribution.main") | .values.id'`

invalidate:
	aws cloudfront create-invalidation --distribution-id={{ distribution_id }} --paths /\* >/dev/null 2>&1

sync:
	cd site && aws s3 sync . s3://${TF_VAR_site_url}
	s3cmd --recursive modify --add-header="Cache-Control:max-age=86400" s3://${TF_VAR_site_url}

deploy: sync invalidate
