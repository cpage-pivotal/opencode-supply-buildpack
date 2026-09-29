#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
manifest="${repo_dir}/config/dependencies.json"

jq -e '
  .schemaVersion == 1
  and (.dependencies | keys == ["jq", "opencode"])
  and all(.dependencies[];
    (.version | type == "string" and length > 0)
    and (.failOnUpdate | type == "boolean")
    and (.license | type == "string" and length > 0)
    and (.purl | type == "string" and startswith("pkg:"))
    and (.assets | has("amd64") and has("arm64"))
    and all(.assets[];
      (.url | startswith("https://"))
      and (.sha256 | test("^[a-f0-9]{64}$"))
      and (.filename | type == "string" and length > 0)
    )
  )
  and (.dependencies.opencode.sourceCommit | test("^[a-f0-9]{40}$"))
  and (.dependencies.opencode.security.minimumSecureVersion
    | test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))
  and (.dependencies.opencode.security.fixedAdvisories | length > 0)
  and all(.dependencies.opencode.security.fixedAdvisories[];
    (.id | test("^GHSA-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}$"))
    and (.affectedVersions | type == "string" and length > 0)
    and (.url | startswith("https://github.com/anomalyco/opencode/security/advisories/"))
  )
' "${manifest}" >/dev/null

version_at_least() {
  local actual=$1 minimum=$2 actual_major actual_minor actual_patch
  local minimum_major minimum_minor minimum_patch
  IFS=. read -r actual_major actual_minor actual_patch <<< "${actual}"
  IFS=. read -r minimum_major minimum_minor minimum_patch <<< "${minimum}"
  [ "${actual_major}" -gt "${minimum_major}" ] \
    || { [ "${actual_major}" -eq "${minimum_major}" ] \
      && [ "${actual_minor}" -gt "${minimum_minor}" ]; } \
    || { [ "${actual_major}" -eq "${minimum_major}" ] \
      && [ "${actual_minor}" -eq "${minimum_minor}" ] \
      && [ "${actual_patch}" -ge "${minimum_patch}" ]; }
}

manifest_opencode=$(jq -r '.dependencies.opencode.version' "${manifest}")
minimum_secure_opencode=$(jq -r \
  '.dependencies.opencode.security.minimumSecureVersion' "${manifest}")
version_at_least "${manifest_opencode}" "${minimum_secure_opencode}" || {
  echo "OpenCode ${manifest_opencode} is below the security floor ${minimum_secure_opencode}" >&2
  exit 1
}

# jq is pinned twice: in the manifest, and in lib/installer.sh, which has to
# install jq before it can read the manifest.
source "${repo_dir}/lib/installer.sh"
for arch in amd64 arm64; do
  IFS=$'\t' read -r bootstrap_filename bootstrap_url bootstrap_sha \
    < <(bootstrap_jq_metadata "${arch}")
  if [ "${bootstrap_filename}" != "$(dependency_value "${manifest}" jq "${arch}" filename)" ] \
    || [ "${bootstrap_url}" != "$(dependency_value "${manifest}" jq "${arch}" url)" ] \
    || [ "${bootstrap_sha}" != "$(dependency_value "${manifest}" jq "${arch}" sha256)" ]; then
    echo "Bootstrap metadata drift for jq/${arch}" >&2
    exit 1
  fi
done

echo "Dependency metadata verified"
