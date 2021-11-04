# -*- makefile -*-

help:
	just --list

serve:
	cd site && python -m http.server 8080

invalidate:
	aws cloudfront create-invalidation --distribution-id=${CLOUDFRONT_DISTRIBUTION_ID} --paths /\* >/dev/null 2>&1

sync:
	cd site && aws s3 sync . s3://${SITE_URL} --acl public-read
	s3cmd --recursive modify --add-header="Cache-Control:max-age=86400" s3://${SITE_URL}

deploy: sync invalidate

tf-apply:
	cd infra && terraform apply

tf-plan:
	cd infra && terraform plan
