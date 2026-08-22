#!/bin/sh
# verify-skills-locked: the bot must not be able to give itself new skills.
#
# Run from the repository root. Used by the `Skills Lockdown` CI job on every
# pull request and on main, and runnable by hand:
#
#     sh builder/verify-skills-locked.sh
#
# Ported from claw-code-local, adapted to this bot: one skill (`mocker`), one
# ConfigMap (claw-mock-skill-mocker), one deployment.
#
# WHAT THIS PROVES, AND WHAT IT DOES NOT
# --------------------------------------
# Every capability the bot has is supposed to be in this repository and to
# have gone through a pull request. A skill the agent acquires at RUNTIME is
# neither — and it is the shortest way around every other control: a skill is
# just instructions the agent will follow, so one it wrote for itself can tell
# it to do anything the sandbox physically permits.
#
# These are STATIC checks over the repository:
#
#   1. the image keeps only the skills BUNDLED_SKILLS_ALLOWED names (it names
#      none), and the Dockerfile still asserts the strip took effect — the
#      removal alone is not enough, because `rm -rf` on a path upstream has
#      moved exits 0 and removes nothing, which is silent and total failure
#   2. no self-extension skill is re-enabled through the plugin allowlist
#   3. the skills loadable in the pod are EXACTLY this bot's own
#   4. the init container makes workspace/skills root-owned and read-only,
#      AFTER the recursive chown that would otherwise undo it
#
# The dynamic half — actually trying to defeat the lockdown as uid 1000 —
# is builder/verify-lockdown-effective.sh, which runs inside the built image
# because it needs the image to exist.
set -eu

FAIL=0
ALLOW_FILE="builder/BUNDLED_SKILLS_ALLOWED"
DOCKERFILE="builder/Dockerfile"
CONFIG="k8s/010-openclaw-config.yaml"
DEPLOYMENT="k8s/020-deployment.yaml"
LOCKDOWN="builder/lock-skill-dirs.sh"
# Sentinels the guarded code emits, so removing a guard is itself a CI failure
# rather than a quiet loss of coverage.
ASSERT_SENTINEL="SKILLS-LOCKED-ASSERT"
READONLY_SENTINEL="SKILLS-DIR-READONLY"
# Skills that exist to let an agent acquire more capability. Named because
# keeping one would defeat the whole control.
SELF_EXTENSION="mcporter skill-creator"

fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
ok()   { echo "  ok:   $*"; }

# Comments stripped: a guard you can satisfy by writing prose about it is not
# a guard.
uncommented() { sed 's/#.*//' "$1"; }

echo "== 1. the image keeps only the bundled skills the allowlist names =="
if [ ! -f "$ALLOW_FILE" ]; then
  fail "$ALLOW_FILE is missing — the strip has no list to work from"
else
  KEPT="$(sed 's/#.*//' "$ALLOW_FILE" | awk 'NF' | sort -u || true)"
  if [ -z "$KEPT" ]; then
    ok "$ALLOW_FILE keeps no bundled skill — the bot has only its own"
  else
    ok "$ALLOW_FILE keeps: $(echo "$KEPT" | tr '\n' ' ')"
    for bad in $SELF_EXTENSION; do
      for k in $KEPT; do
        [ "$k" = "$bad" ] && fail "$ALLOW_FILE keeps '$k', which exists to let
        the agent acquire capability at runtime"
      done
    done
  fi
fi

if grep -q "COPY BUNDLED_SKILLS_ALLOWED" "$DOCKERFILE"; then
  ok "$DOCKERFILE reads the list from $ALLOW_FILE"
else
  fail "$DOCKERFILE does not COPY BUNDLED_SKILLS_ALLOWED. The list must be
        the source of truth, not a second copy inside the build"
fi

if uncommented "$DOCKERFILE" | grep -q "rm -rf"; then
  ok "$DOCKERFILE removes what the allowlist does not name"
else
  fail "$DOCKERFILE has no removal of unlisted skills at all"
fi

if uncommented "$DOCKERFILE" | grep -q "find /app -name SKILL.md"; then
  ok "the removal is driven by a search for loadable skills, not one directory"
else
  fail "$DOCKERFILE does not locate skills with 'find /app -name SKILL.md'.
        Skills also ship inside extensions and in the /app/dist mirror, so a
        strip of /app/skills alone reports success and removes nothing there"
fi

if uncommented "$DOCKERFILE" | grep -q "$ASSERT_SENTINEL"; then
  ok "$DOCKERFILE still asserts the removal took effect ($ASSERT_SENTINEL)"
else
  fail "$DOCKERFILE has no $ASSERT_SENTINEL assertion in its build steps.
        'rm -rf' on a moved path exits 0 and removes nothing — without the
        assertion every bundled skill ships and the build stays green"
fi

if uncommented "$DOCKERFILE" | grep -q "exit 1"; then
  ok "the assertion can fail the build"
else
  fail "no 'exit 1' in $DOCKERFILE's build steps — an assertion that only
        prints is not an assertion"
fi

echo "== 2. no self-extension skill is re-enabled through the plugin allowlist =="
if ! grep -q '"allow"' "$CONFIG"; then
  ok "no plugin \"allow\" list in $CONFIG — nothing is granted at runtime"
else
  ok "plugin allowlist present: $(grep '"allow"' "$CONFIG" | head -1 | cut -c1-90)"
  for skill in $SELF_EXTENSION; do
    if grep '"allow"' -A4 "$CONFIG" | grep -q "\"$skill\""; then
      fail "$skill appears in the plugin allowlist in $CONFIG"
    else
      ok "$skill is not in the plugin allowlist"
    fi
  done
fi

echo "== 3. the loadable skills are exactly the ones this repo defines =="
MOUNTED="$(grep -oE 'workspace/skills/[a-z0-9-]+' "$DEPLOYMENT" | sed 's#.*/##' | sort -u || true)"
if [ -z "$MOUNTED" ]; then
  fail "no skill mounts found in $DEPLOYMENT — the grep above has gone stale"
else
  ok "skills mounted: $(echo "$MOUNTED" | tr '\n' ' ')"
  for name in $MOUNTED; do
    if grep -q "claw-mock-skill-$name" "$DEPLOYMENT"; then
      ok "$name ← ConfigMap claw-mock-skill-$name"
    else
      fail "skill '$name' is mounted but has no claw-mock-skill-$name volume —
            it would come from somewhere unreviewed"
    fi
  done
  # And the other direction: a ConfigMap defining a skill nobody mounts is a
  # capability sitting in the cluster that no manifest accounts for.
  for cm in $(grep -ohE 'claw-mock-skill-[a-z0-9-]+' k8s/*.yaml | sort -u); do
    name="${cm#claw-mock-skill-}"
    if echo "$MOUNTED" | grep -qx "$name"; then
      ok "$cm is mounted"
    else
      fail "$cm defines a skill that $DEPLOYMENT never mounts"
    fi
  done
fi

echo "== 4. no FURTHER skill can be added at runtime =="
if [ ! -f "$LOCKDOWN" ]; then
  fail "$LOCKDOWN is missing — nothing seals the skills directories"
else
  ok "$LOCKDOWN exists"
  if grep -q "chown -R 0:0" "$LOCKDOWN" && grep -q "chmod 0555" "$LOCKDOWN"; then
    ok "the lockdown makes the directories root-owned AND read-only"
  else
    fail "$LOCKDOWN does not both chown 0:0 and chmod 0555. Ownership matters
          as much as the mode: a directory the agent's uid owns can simply be
          chmod'ed back, so 0555 alone is decoration"
  fi
  if grep -q "$READONLY_SENTINEL" "$LOCKDOWN"; then
    ok "$LOCKDOWN reports $READONLY_SENTINEL"
  else
    fail "$LOCKDOWN does not emit $READONLY_SENTINEL"
  fi
fi

if grep -q "lock-skill-dirs" "$DEPLOYMENT"; then
  ok "$DEPLOYMENT runs the lockdown"
else
  fail "$DEPLOYMENT never runs lock-skill-dirs — the directories stay writable"
fi

# ORDERING IS THE WHOLE THING. A recursive chown to the agent AFTER the lock
# hands every directory straight back, and the manifest still reads as though
# it were locked.
CHOWN_LINE="$(grep -n 'chown -R 1000:1000' "$DEPLOYMENT" | tail -1 | cut -d: -f1 || true)"
LOCK_LINE="$(grep -n 'lock-skill-dirs' "$DEPLOYMENT" | tail -1 | cut -d: -f1 || true)"
if [ -n "$CHOWN_LINE" ] && [ -n "$LOCK_LINE" ]; then
  if [ "$LOCK_LINE" -gt "$CHOWN_LINE" ]; then
    ok "the lockdown runs AFTER the recursive chown (line $LOCK_LINE > $CHOWN_LINE)"
  else
    fail "the recursive chown at line $CHOWN_LINE runs AFTER the lockdown at
          line $LOCK_LINE and undoes it"
  fi
fi

if grep -q "refusing to start" "$DEPLOYMENT"; then
  ok "the init container fails closed if the lockdown binary is missing"
else
  fail "$DEPLOYMENT starts even when lock-skill-dirs is absent from the image —
        it would come up with the directories writable and nothing reporting it"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "PASS: the bot cannot give itself a skill."
  exit 0
fi
echo "FAILED: $FAIL check(s)." >&2
exit 1
