# Entry points for running the platform locally. CI calls the same targets,
# so what passes here is what passes there.

CLUSTER              := gitops-platform
KIND_NODE            := kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed
ARGOCD_CHART_VERSION := 10.9.2
REVISION             ?= main

.DEFAULT_GOAL := help
.PHONY: help up cluster argocd root wait smoke status password validate down

help: ## Show the available targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

up: cluster argocd root wait ## Create the cluster and deploy everything, then wait until it is healthy
	@echo
	@echo "Ready. Argo CD: http://argocd.localtest.me:8080 (user admin, password: make password)"

cluster: ## Create the kind cluster
	kind create cluster --config bootstrap/kind-cluster.yaml --image $(KIND_NODE)

argocd: ## Install Argo CD, the one component not managed from git
	helm upgrade --install argocd argo-cd \
	  --repo https://argoproj.github.io/argo-helm --version $(ARGOCD_CHART_VERSION) \
	  --namespace argocd --create-namespace \
	  --values bootstrap/argocd-values.yaml --wait --timeout 10m

root: ## Apply the root Application at REVISION (default main)
	sed 's/: main$$/: $(REVISION)/' bootstrap/root-app.yaml | kubectl apply -f -

wait: ## Wait until every Application is synced and healthy
	scripts/wait-for-apps.sh

smoke: ## Call each service through the gateway
	scripts/smoke-test.sh

status: ## List Applications with their sync and health status
	@kubectl get applications -n argocd

password: ## Print the initial Argo CD admin password
	@kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d; echo

validate: ## Render everything and validate it against the Kubernetes and CRD schemas
	scripts/validate.sh

down: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER)
