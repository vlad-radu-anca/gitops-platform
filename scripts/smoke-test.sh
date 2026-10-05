#!/usr/bin/env bash
# Calls each service through Envoy Gateway on localhost:8080, the same path a
# browser takes. --resolve pins the hostnames to 127.0.0.1, so the test does
# not depend on DNS for localtest.me.
set -euo pipefail

GATEWAY="${GATEWAY:-127.0.0.1:8080}"
PORT="${GATEWAY##*:}"
failed=0

call() {  # host path -> prints the response body, then the HTTP status on a final line
  curl -s --max-time 10 --resolve "$1:$PORT:${GATEWAY%%:*}" -w '\n%{http_code}' "http://$1:$PORT$2"
}

check_version() {  # env expected
  local out body code version
  out=$(call "podinfo-$1.localtest.me" /version) || true
  # podinfo pretty-prints its JSON over several lines: the status is the last
  # line, the body is everything before it.
  code=$(tail -n1 <<<"$out"); body=$(sed '$d' <<<"$out")
  version=$(jq -r '.version // empty' <<<"$body" 2>/dev/null || true)
  if [ "$code" = "200" ] && [ "$version" = "$2" ]; then
    echo "ok    podinfo-$1 serves $version"
  else
    echo "FAIL  podinfo-$1: HTTP $code, version '$version', expected $2"; failed=1
  fi
}

check_reachable() {  # name host path allowed-codes
  local code
  code=$(call "$2" "$3" | tail -n1) || true
  if [[ " $4 " == *" $code "* ]]; then
    echo "ok    $1 answers HTTP $code"
  else
    echo "FAIL  $1: HTTP $code, expected one of: $4"; failed=1
  fi
}

# Promotion: prod is held one version behind dev and staging.
check_version dev     "$(grep -m1 'tag:' environments/dev/podinfo.yaml     | awk '{print $2}')"
check_version staging "$(grep -m1 'tag:' environments/staging/podinfo.yaml | awk '{print $2}')"
check_version prod    "$(grep -m1 'tag:' environments/prod/podinfo.yaml    | awk '{print $2}')"

# Kibana answers 401 without credentials, which still proves the route works.
check_reachable kibana  kibana.localtest.me  /api/status "200 401"
check_reachable argocd  argocd.localtest.me  /healthz    "200"
if kubectl get application monitoring -n argocd >/dev/null 2>&1; then
  check_reachable grafana grafana.localtest.me /api/health "200"
fi

exit "$failed"
