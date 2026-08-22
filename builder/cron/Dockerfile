# The CronJob image: kubectl and a shell, and nothing else.
#
# WHY THIS EXISTS
# The db-mocker CronJob is an ORCHESTRATOR, not an agent. `cron-mock-spawn`
# finds the running claw-mock pod and does the real work inside it via
# `kubectl exec` — the agent runtime, the model calls, sqlcmd and the mock
# databases all live over there. What runs HERE is one bash script and a
# couple of kubectl calls.
#
# It was running from the full agent image, on an hourly schedule, to execute
# a workload that is a pod lookup and an exec. That image carries the openclaw
# runtime, node, sqlcmd — and, since charts were added, chromium and its
# graphics libraries. None of it is reachable from this entrypoint, and the
# browser in particular is several hundred megabytes that this pod pulls and
# never runs.
#
# WHAT MUST STAY TRUE
# The COPY below is the transitive closure of what cron-mock-spawn needs, and
# builder/verify-cron-image.sh derives that closure again from the script and
# fails if the two have drifted. Adding a command to the spawner without
# adding it here would otherwise fail on the hour, in a CronJob nobody is
# watching, rather than in CI.
#
# mock-runner is deliberately NOT here. It executes inside the main pod via
# kubectl exec, so it ships in the agent image and would be dead weight in
# this one.
#
# ca-certificates is required, not optional: kubectl talks to the API server
# over TLS, and an image without a trust store fails every call with a
# verification error.
FROM alpine:3.22

# Pinned, not resolved from dl.k8s.io/release/stable.txt at build time. The
# client has to match the AKS version this project creates (aks_version in
# main.tf), and "whatever is stable today" drifts away from that silently —
# the pair is one decision, made in /VERSIONS.
ARG KUBECTL_VERSION
ARG TARGETARCH
RUN set -eux; \
    test -n "${KUBECTL_VERSION}"; \
    apk add --no-cache ca-certificates bash; \
    arch="${TARGETARCH:-arm64}"; \
    wget -qO /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${arch}/kubectl"; \
    chmod 0755 /usr/local/bin/kubectl; \
    kubectl version --client=true >/dev/null

# Installed suffix-stripped and executable, exactly as the agent image does
# it, so the CronJob `command:` is identical in both.
COPY --chmod=0755 cron-mock-spawn.sh /usr/local/bin/cron-mock-spawn

# Nothing here needs root, and this image holds a token: the CronJob mounts
# the service account for the API calls above. uid 1000 matches the agent
# image so anything shared keeps the same ownership either side.
RUN adduser -D -u 1000 claw
USER 1000
