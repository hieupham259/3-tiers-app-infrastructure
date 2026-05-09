ENV ?= development
ENV_DIR := envs/$(ENV)
TF := terraform -chdir=$(ENV_DIR)

.PHONY: help init fmt validate plan apply destroy lint sync-check clean

help:
	@echo "Targets (override env via ENV=development|production):"
	@echo "  init        - terraform init for ENV"
	@echo "  fmt         - terraform fmt -recursive (repo-wide)"
	@echo "  validate    - terraform validate for ENV"
	@echo "  plan        - terraform plan for ENV"
	@echo "  apply       - terraform apply (LOCAL ONLY for debug; production through CI/CD)"
	@echo "  destroy     - terraform destroy (development only)"
	@echo "  lint        - tflint on modules + envs"
	@echo "  sync-check  - verify envs/development and envs/production are identical"
	@echo "  clean       - remove .terraform dirs + tfplan files"

init:
	$(TF) init

fmt:
	terraform fmt -recursive

validate:
	$(TF) validate

plan:
	$(TF) plan -out=tfplan

apply:
	$(TF) apply tfplan

destroy:
	@if [ "$(ENV)" = "production" ]; then echo "Refusing to destroy production from local"; exit 1; fi
	$(TF) destroy

lint:
	tflint --recursive

sync-check:
	bash scripts/verify-envs-in-sync.sh

clean:
	find . -type d -name '.terraform' -prune -exec rm -rf {} +
	find . -type f -name 'tfplan' -delete
