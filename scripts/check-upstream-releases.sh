#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
manifest="${repo_dir}/config/dependencies.json"
fail_on_update=false
[ "${1:-}" = "--fail-on-update" ] && fail_on_update=true

github_api() {
  local path=$1
  local args=(
    --fail --silent --show-error --location
    --connect-timeout 15 --max-time 60
    -H "Accept: application/vnd.github+json"
  )
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  curl "${args[@]}" "https://api.github.com/${path}"
}

# OpenCode follows the version the ACP registry publishes, which is what Spring AI ACP
# Harness Client pins and verifies. GitHub's "latest" release still marks the 1.x line
# after the registry moved to 2.x, so it is shown for information only.
registry_url=https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json

registry_version() {
  local agent=$1
  curl --fail --silent --show-error --location \
    --connect-timeout 15 --max-time 60 "${registry_url}" \
    | jq -er --arg agent "${agent}" '.agents[] | select(.id == $agent) | .version'
}

updates=0
while IFS=$'\t' read -r dependency source repository prefix; do
  pinned=$(jq -r --arg dependency "${dependency}" \
    '.dependencies[$dependency].version' "${manifest}")
  blocking=$(jq -r --arg dependency "${dependency}" \
    '.dependencies[$dependency].failOnUpdate' "${manifest}")
  latest_tag=$(github_api "repos/${repository}/releases/latest" | jq -er '.tag_name')
  github_latest=${latest_tag#"${prefix}"}
  if [ "${source}" = registry ]; then
    latest=$(registry_version "${dependency}")
    if [ "${github_latest}" != "${latest}" ]; then
      echo "${dependency}: GitHub's latest release is ${github_latest} (informational; pins follow the ACP registry)"
    fi
  else
    latest=${github_latest}
  fi
  if [ "${pinned}" = "${latest}" ]; then
    echo "${dependency}: current (${pinned})"
  elif [ "${blocking}" = true ]; then
    echo "${dependency}: update available (${pinned} -> ${latest})"
    updates=$((updates + 1))
  else
    echo "${dependency}: update available (${pinned} -> ${latest}) [non-blocking]"
  fi
done <<'EOF'
opencode	registry	anomalyco/opencode	v
jq	github	jqlang/jq	jq-
EOF

pinned_opencode=$(jq -r '.dependencies.opencode.version' "${manifest}")
pinned_commit=$(jq -r '.dependencies.opencode.sourceCommit' "${manifest}")
tag_object=$(github_api \
  "repos/anomalyco/opencode/git/ref/tags/v${pinned_opencode}")
tag_type=$(jq -r '.object.type' <<< "${tag_object}")
tag_sha=$(jq -r '.object.sha' <<< "${tag_object}")
if [ "${tag_type}" = "tag" ]; then
  tag_sha=$(github_api "repos/anomalyco/opencode/git/tags/${tag_sha}" \
    | jq -er '.object.sha')
fi
[ "${tag_sha}" = "${pinned_commit}" ] || {
  echo "Pinned OpenCode source commit does not match tag v${pinned_opencode}" >&2
  exit 1
}
echo "opencode: tag v${pinned_opencode} matches pinned source commit"

if [ "${updates}" -gt 0 ] && [ "${fail_on_update}" = true ]; then
  echo "${updates} pinned dependency update(s) require review" >&2
  exit 1
fi
