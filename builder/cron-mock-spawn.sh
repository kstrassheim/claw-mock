#!/bin/bash
# cron-mock-spawn: invoked by the db-mocker CronJob every hour.
#
# Finds the running claw-mock pod and backgrounds /usr/local/bin/mock-runner
# inside it. The mock run executes as a subprocess of the main container —
# it shares the pod's network, secrets (SQL credentials, MINIMAX_API_KEY),
# config, and persistent workspace volume. This script then exits, so the
# CronJob pod completes in seconds while the mock run continues in the
# main pod.
set -euo pipefail

NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)

# Resolve the running main pod (Deployment.metadata.name == "claw-mock",
# pod selector app=claw-mock).
CLAW_MOCK_POD=$(kubectl -n "$NAMESPACE" get pod \
    -l app=claw-mock \
    -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' \
    | awk '{print $1}')
test -n "$CLAW_MOCK_POD" || { echo "ERROR: no Running claw-mock pod found in $NAMESPACE" >&2; exit 1; }
echo "claw-mock pod: $CLAW_MOCK_POD"

REMOTE_CMD='setsid bash -c '"'"'nohup /usr/local/bin/mock-runner >/dev/null 2>&1 </dev/null &'"'"' >/dev/null 2>&1 </dev/null &'

# Container name inside the pod is 'claw-mock'.
kubectl -n "$NAMESPACE" exec "$CLAW_MOCK_POD" -c claw-mock -- bash -c "$REMOTE_CMD"
echo "spawned mock run in $CLAW_MOCK_POD"
