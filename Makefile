SHELL := /bin/bash
# Override any environment KUBECONFIG with local path
override KUBECONFIG := $(shell pwd)/../k3s-infra/kubeconfig
KUBE := KUBECONFIG=$(KUBECONFIG) kubectl
HELM := KUBECONFIG=$(KUBECONFIG) helm

.PHONY: help deploy apply-pvcs install-helm wait-for-ready status destroy clean helm-template

help: ## Show this help message
	@echo "Jellyfin Media Server Deployment (Helm)"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

deploy: apply-pvcs install-helm wait-for-ready ## Full deploy: PVCs + helm chart
	@echo "✓ Jellyfin fully deployed via helm"

apply-pvcs: ## Apply PVC manifests
	@$(KUBE) apply -f manifests/

install-helm: ## Install/upgrade Jellyfin helm chart
	@echo "Installing Jellyfin helm chart..."
	@$(HELM) repo add jellyfin https://jellyfin.github.io/jellyfin-helm 2>/dev/null || true
	@$(HELM) repo update jellyfin
	@$(HELM) upgrade --install jellyfin jellyfin/jellyfin \
		--namespace jellyfin \
		--create-namespace \
		--values helm/values.yaml \
		--wait \
		--timeout 5m

wait-for-ready: ## Wait for Jellyfin pod to be ready
	@echo "Waiting for Jellyfin pod to be ready..."
	@$(KUBE) wait --namespace jellyfin --for=condition=ready pod --selector=app.kubernetes.io/name=jellyfin --timeout=300s 2>/dev/null || true

status: ## Show Jellyfin status
	@echo "Jellyfin Resources:"
	@$(KUBE) get pods,svc,pvc -n jellyfin
	@echo ""
	@echo "Helm Release:"
	@$(HELM) list -n jellyfin

helm-template: ## Preview helm chart output
	@$(HELM) template jellyfin jellyfin/jellyfin --values helm/values.yaml --namespace jellyfin

destroy: ## Remove Jellyfin (WARNING: deletes PVCs and data!)
	@echo "WARNING: This will delete all Jellyfin data!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		$(HELM) uninstall jellyfin -n jellyfin 2>/dev/null || echo "Not found"; \
		$(KUBE) delete namespace jellyfin --timeout=120s 2>/dev/null || echo "Already removed"; \
	else \
		echo "Cancelled."; \
	fi

clean: ## Remove Jellyfin but keep PVCs
	@echo "Removing Jellyfin helm release (keeping PVCs)..."
	@$(HELM) uninstall jellyfin -n jellyfin 2>/dev/null || echo "Release not found"
