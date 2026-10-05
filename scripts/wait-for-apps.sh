#!/usr/bin/env bash
# Waits until every Argo CD Application is Synced and Healthy. On timeout it
# prints what is still pending and why, then exits non-zero.
set -euo pipefail

NAMESPACE="${NAMESPACE:-argocd}"
TIMEOUT="${TIMEOUT:-1500}"   # seconds
# root + 10 platform applications + 3 podinfo environments
MIN_APPS="${MIN_APPS:-14}"
INTERVAL=20

apps_json() { kubectl get applications -n "$NAMESPACE" -o json; }

print_table() {
  apps_json | jq -r '
    ["APPLICATION","WAVE","SYNC","HEALTH"],
    (.items | sort_by((.metadata.annotations["argocd.argoproj.io/sync-wave"] // "0") | tonumber) | .[] |
      [.metadata.name,
       (.metadata.annotations["argocd.argoproj.io/sync-wave"] // "-"),
       (.status.sync.status // "Unknown"),
       (.status.health.status // "Unknown")])
    | @tsv' | column -t
}

diagnose() {
  echo
  echo "=== Applications that are not synced and healthy"
  apps_json | jq -r '.items[]
    | select(.status.sync.status != "Synced" or .status.health.status != "Healthy")
    | "\n--- \(.metadata.name): sync=\(.status.sync.status) health=\(.status.health.status)",
      ((.status.conditions // [])[] | "  condition: \(.type): \(.message)"),
      (if .status.operationState.message then "  last operation: \(.status.operationState.message)" else empty end),
      ((.status.resources // [])[] | select((.health.status // "Healthy") != "Healthy" or .status != "Synced")
        | "  resource \(.kind)/\(.name) in \(.namespace // "-"): sync=\(.status) health=\(.health.status // "-") \(.health.message // "")")'
  echo
  echo "=== Pods that are not ready"
  kubectl get pods -A --no-headers | awk '$4 != "Running" && $4 != "Completed" || $3 !~ /^([0-9]+)\/\1$/' || true
  echo
  echo "=== Recent warning events"
  kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -25 || true
}

deadline=$(( $(date +%s) + TIMEOUT ))
while true; do
  json=$(apps_json)
  total=$(jq '.items | length' <<<"$json")
  ready=$(jq '[.items[] | select(.status.sync.status == "Synced" and .status.health.status == "Healthy")] | length' <<<"$json")
  echo "$(date +%H:%M:%S)  ${ready}/${total} applications synced and healthy (expecting at least ${MIN_APPS})"

  if [ "$total" -ge "$MIN_APPS" ] && [ "$ready" -eq "$total" ]; then
    echo; print_table
    exit 0
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "Timed out after ${TIMEOUT}s"; echo; print_table; diagnose
    exit 1
  fi
  sleep "$INTERVAL"
done
