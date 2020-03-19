OUTPUT_DIR:=dist

COLOR_GREEN=$(shell echo "\033[0;32m")
COLOR_NONE=$(shell echo "\033[0m")

.PHONY: help

help:
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.DEFAULT_GOAL := help

clean: ## Cleanup generated files
	@echo '$(COLOR_GREEN)==> Cleaning up ${SITE_URL} artifacts$(COLOR_NONE)'
	@rm -rf $(OUTPUT_DIR)
	@rm -rf resources

build: ## Build the static version of the site
	@echo '$(COLOR_GREEN)==> Building ${SITE_URL}$(COLOR_NONE)'
	@hugo --baseURL="//${SITE_URL}" --destination "${OUTPUT_DIR}" --minify

serve: ## Start a local development server
	@echo '$(COLOR_GREEN)==> Starting local server$(COLOR_NONE)'
	@hugo serve

sync: ## Synchronize local static output with live site
	@echo '$(COLOR_GREEN)==> Syncing ${OUTPUT_DIR} contents to S3 bucket ${SITE_URL}$(COLOR_NONE)'
	@aws s3 sync ${OUTPUT_DIR} s3://${SITE_URL}
	@echo '$(COLOR_GREEN)==> Invalidating ${SITE_URL} CloudFront distribution$(COLOR_NONE)'
	@aws cloudfront create-invalidation --distribution-id=${CLOUDFRONT_DISTRIBUTION_ID} --paths /\*

deploy: clean build sync ## Build and deploy the site to AWS

tf-apply: ## Provision requisite AWS resources
	@echo '$(COLOR_GREEN)==> Provisioning ${SITE_URL} infrastructure$(COLOR_NONE)'
	@cd infra && terraform apply

tf-plan: ## Show proposed changes to AWS resources
	@echo '$(COLOR_GREEN)==> Inspecting ${SITE_URL} infrastructure$(COLOR_NONE)'
	@cd infra && terraform plan
