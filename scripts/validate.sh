#!/usr/bin/env bash
# Static checks, no cluster needed: renders the app-of-apps and every chart it
# deploys from this repository's values, then validates the output against the
# Kubernetes API schema and the CRD schemas (Argo CD, External Secrets, Gateway
# API, Envoy Gateway). Chart versions are read from the Application manifests,
# so there is one place to bump them.
set -euo pipefail

K8S_VERSION="${K8S_VERSION:-1.36.0}"
CRD_CATALOG='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
failed=0

kc() {
  kubeconform -strict -summary -output text \
    -kubernetes-version "$K8S_VERSION" \
    -schema-location default -schema-location "$CRD_CATALOG" "$@"
}
step() { echo; echo "== $*"; }
check() { if ! "$@"; then failed=1; fi; }

version_of() {  # template-file chart-name
  grep -A2 "chart: $2" "charts/apps/templates/$1" | awk '/targetRevision:/ {print $2; exit}'
}

step "app-of-apps chart"
check helm lint charts/apps
helm template root charts/apps > "$WORK/apps.yaml"
check kc "$WORK/apps.yaml"

step "plain manifests"
for f in manifests/*/*.yaml; do check kc "$f"; done

step "podinfo, per environment"
PODINFO_VERSION=$(version_of podinfo.yaml podinfo)
helm pull podinfo --repo https://stefanprodan.github.io/podinfo --version "$PODINFO_VERSION" --untar --untardir "$WORK"
for env in dev staging prod; do
  echo "-- $env"
  helm template podinfo "$WORK/podinfo" -f "environments/$env/podinfo.yaml" > "$WORK/podinfo-$env.yaml"
  check kc "$WORK/podinfo-$env.yaml"
done

step "platform-stack"
STACK_VERSION=$(version_of platform-stack.yaml platform-stack)
helm pull oci://ghcr.io/vlad-radu-anca/platform-stack --version "$STACK_VERSION" --untar --untardir "$WORK"
helm template demo "$WORK/platform-stack" -f environments/platform-stack/values.yaml > "$WORK/platform-stack.yaml"
check kc "$WORK/platform-stack.yaml"
# Only public images may be deployed; the product images are not published.
# Matches both "image: x" and the list-item form "- image: x" that some charts use.
IMAGE_LINES='^[[:space:]]*(-[[:space:]]+)?image:'
if grep -E "$IMAGE_LINES" "$WORK/platform-stack.yaml" | grep -q 'vlad-radu-anca/'; then
  echo "FAIL: platform-stack would deploy a non-public image:"
  grep -E "$IMAGE_LINES" "$WORK/platform-stack.yaml" | grep 'vlad-radu-anca/' | sort -u
  failed=1
else
  echo "Images deployed by platform-stack (all public):"
  grep -E "$IMAGE_LINES" "$WORK/platform-stack.yaml" | sed -E 's/.*image:[[:space:]]*//; s/"//g' | sort -u | sed 's/^/  /'
fi

echo
if [ "$failed" -eq 0 ]; then echo "All checks passed."; else echo "Some checks failed."; fi
exit "$failed"
