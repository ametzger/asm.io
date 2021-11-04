# -*- makefile -*-

help:
	just --list

serve:
	cd site && python -m http.server 8080

invalidate:
	aws cloudfront create-invalidation --distribution-id=${CLOUDFRONT_DISTRIBUTION_ID} --paths /\* >/dev/null 2>&1

sync:
	cd site && aws s3 sync . s3://${SITE_URL} --acl public-read
	aws s3 ls s3://${SITE_URL} --recursive | awk '{cmd="aws s3api put-object-acl --acl public-read --bucket ${SITE_URL} --key "$4; system(cmd)}'
	s3cmd --recursive modify --add-header="Cache-Control:max-age=86400" s3://${SITE_URL}

deploy: sync invalidate

tf-apply:
	cd infra && terraform apply

tf-plan:
	cd infra && terraform plan
