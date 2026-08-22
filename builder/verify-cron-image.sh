#!/bin/sh
# verify-cron-image: the CronJob image must carry everything its entrypoint
# reaches, and nothing it does not.
#
# Run from the repository root:
#     sh builder/verify-cron-image.sh
#
# WHY THIS EXISTS
# ---------------
# The db-mocker CronJob used to run the full agent image to execute a pod
# lookup and a `kubectl exec`. It now runs a slim one — which is only correct
# for as long as that slim image still carries what the entrypoint needs.
#
# Nothing derives that list at build time. So a command added to
# cron-mock-spawn without a matching line in cron/Dockerfile fails ON THE
# HOUR, in a CronJob pod nobody is watching, and the symptom is "the mock run
# stopped happening" rather than an error anybody sees. This derives the
# closure from the script instead and fails in CI.
#
# THE OTHER DIRECTION MATTERS TOO. A slim image that quietly grows back into
# the full one has lost the point of existing, so anything COPYed here that
# the entrypoint cannot reach is also a failure.
set -eu

FAIL=0
CRON_DF="builder/cron/Dockerfile"
ENTRY="builder/cron-mock-spawn.sh"
MANIFEST="k8s/050-db-mocker.yaml"

fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
ok()   { echo "  ok:   $*"; }

# Comments stripped before every grep. This file explains what the image
# deliberately does NOT carry, and a check that matched its own prose would
# fail on the explanation — the same trap verify-skills-locked.sh names.
uncommented() { sed 's/#.*//' "$1"; }
DF_CODE="$(uncommented "$CRON_DF")"

[ -f "$CRON_DF" ] || { echo "FAIL: $CRON_DF is missing" >&2; exit 1; }
[ -f "$ENTRY" ]   || { echo "FAIL: $ENTRY is missing" >&2; exit 1; }

echo "== 1. the entrypoint's commands are in the image =="
# Every external command the spawner invokes. Shell builtins and its own
# control flow are not commands the image has to carry.
BUILTINS="set test echo cat exit local read printf true false cd export"
CMDS="$(sed 's/#.*//' "$ENTRY" \
  | grep -oE '(^|[|;&(]|\$\()[[:space:]]*[a-z][a-z0-9_-]*' \
  | sed -E 's/.*[^a-z0-9_-]//' | sort -u)"

for c in $CMDS; do
  case " $BUILTINS " in *" $c "*) continue ;; esac
  case "$c" in in|do|done|then|else|fi|if|for|while|esac|case|function) continue ;; esac
  # Provided by busybox/coreutils in the base, or installed explicitly.
  case "$c" in
    awk|sed|grep|tr|cut|head|tail|wc|xargs|sort|uniq|mkdir|rm|ln|chmod)
      ok "$c — busybox provides it"; continue ;;
  esac
  if printf '%s\n' "$DF_CODE" | grep -q "$c"; then
    ok "$c — named in $CRON_DF"
  else
    fail "$ENTRY runs '$c', which $CRON_DF never installs. The CronJob would
          fail on the hour with command-not-found, in a pod nobody watches"
  fi
done

echo "== 2. the image carries nothing the entrypoint cannot reach =="
COPIED="$(printf '%s\n' "$DF_CODE" \
  | grep -oE '^COPY[^/]*[[:space:]]([a-zA-Z0-9_.-]+\.sh)' \
  | awk '{print $NF}' | sort -u || true)"
for f in $COPIED; do
  base="$(basename "$f" .sh)"
  if [ "$f" = "$(basename "$ENTRY")" ]; then
    ok "$f — the entrypoint itself"
  elif grep -q "$base" "$ENTRY"; then
    ok "$f — reached from the entrypoint"
  else
    fail "$CRON_DF copies '$f', which $ENTRY never reaches. A slim image that
          grows back into the full one has lost the point of existing"
  fi
done

# mock-runner is the specific one worth naming: it is the obvious thing to
# add here, and it would be wrong. It executes INSIDE the main pod.
if printf '%s\n' "$DF_CODE" | grep -q "mock-runner"; then
  fail "$CRON_DF ships mock-runner. It runs in the MAIN pod via kubectl exec,
        so it belongs to the agent image and is dead weight here"
else
  ok "mock-runner is not shipped here — it runs in the main pod"
fi

echo "== 3. the kubectl client is pinned, not floated =="
if printf '%s\n' "$DF_CODE" | grep -q "ARG KUBECTL_VERSION"; then
  ok "$CRON_DF takes KUBECTL_VERSION as a build arg"
else
  fail "$CRON_DF does not take KUBECTL_VERSION. Resolving 'stable' at build
        time drifts away from the AKS version this project creates"
fi
if printf '%s\n' "$DF_CODE" | grep -q "stable.txt"; then
  fail "$CRON_DF resolves kubectl from stable.txt — that is the drift the
        pin exists to prevent"
else
  ok "kubectl is not resolved from stable.txt"
fi

PIN="$(grep '^KUBECTL_VERSION=' VERSIONS | cut -d= -f2 || true)"
AKS="$(grep -oE 'aks_version[[:space:]]*=[[:space:]]*"[0-9.]+"' main.tf \
       | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
if [ -n "$PIN" ] && [ -n "$AKS" ]; then
  if [ "$PIN" = "$AKS" ]; then
    ok "KUBECTL_VERSION ($PIN) matches aks_version"
  else
    fail "KUBECTL_VERSION is $PIN but aks_version is $AKS. The client this
          image installs talks to that exact server; they are one decision"
  fi
fi

echo "== 4. the CronJob actually uses this image =="
if grep -q "claw-mock-cron" "$MANIFEST"; then
  ok "$MANIFEST points at the cron image"
else
  fail "$MANIFEST does not reference claw-mock-cron — the CronJob is still
        pulling the full agent image, and this image is built for nobody"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: the cron image carries its entrypoint's closure and nothing more."
  exit 0
fi
echo "FAILED: $FAIL check(s)." >&2
exit 1
