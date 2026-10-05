#!/usr/bin/env bash
# Markdown summary of the deployed platform, written to the GitHub Actions
# job summary so a run shows its result without opening the logs.
set -uo pipefail

echo "## Platform deployed from \`${REVISION:-main}\`"
echo
echo "| Application | Wave | Sync | Health |"
echo "|---|---|---|---|"
kubectl get applications -n argocd -o json 2>/dev/null | jq -r '
  .items | sort_by((.metadata.annotations["argocd.argoproj.io/sync-wave"] // "0") | tonumber) | .[] |
  "| \(.metadata.name) | \(.metadata.annotations["argocd.argoproj.io/sync-wave"] // "-") | \(.status.sync.status // "Unknown") | \(.status.health.status // "Unknown") |"'
echo
echo "### Podinfo versions per environment"
echo
echo "| Environment | Image |"
echo "|---|---|"
for env in dev staging prod; do
  img=$(kubectl get deploy podinfo -n "podinfo-$env" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "not deployed")
  echo "| $env | \`$img\` |"
done
