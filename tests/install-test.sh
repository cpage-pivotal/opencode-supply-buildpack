#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source "${repo_dir}/tests/test-helper.sh"
source "${repo_dir}/lib/installer.sh"

# A buildpack directory whose manifest pins a stand-in opencode archive, bundled
# the way the cached release bundles the real one.
fake_buildpack() {
  local bp_dir=$1
  local archive_root=$2
  local filename=opencode-test.tar.gz sha

  mkdir -p "${bp_dir}/config" "${bp_dir}/dependencies"
  tar czf "${bp_dir}/dependencies/${filename}" -C "${archive_root}" .
  sha=$(sha256_file "${bp_dir}/dependencies/${filename}")
  jq -n --arg filename "${filename}" --arg sha "${sha}" '{
    schemaVersion: 1,
    dependencies: {opencode: {
      version: "9.9.9",
      assets: {
        amd64: {filename: $filename, url: "https://example.com/unused", sha256: $sha},
        arm64: {filename: $filename, url: "https://example.com/unused", sha256: $sha}
      }
    }}
  }' > "${bp_dir}/config/dependencies.json"
}

good_archive="${TEST_TMP}/good-archive"
mkdir -p "${good_archive}"
printf '%s\n' '#!/bin/sh' 'echo "9.9.9"' > "${good_archive}/opencode"
chmod 0755 "${good_archive}/opencode"
fake_buildpack "${TEST_TMP}/bp" "${good_archive}"

install_dir="${TEST_TMP}/deps/0"
install_opencode "${install_dir}" "${TEST_TMP}/cache" "${TEST_TMP}/bp" >/dev/null
assert_eq "9.9.9" "$("${install_dir}/bin/opencode" --version)"
assert_eq "9.9.9" "${OPENCODE_RESOLVED_VERSION}"
verify_installation "${install_dir}" >/dev/null || fail "installation did not verify"

# A opencode outside the manifest needs its own URL and checksum.
if OPENCODE_VERSION=1.0.0 install_opencode "${TEST_TMP}/deps/1" "${TEST_TMP}/cache" \
    "${TEST_TMP}/bp" >/dev/null 2>&1; then
  fail "unpinned OPENCODE_VERSION was installed without a checksum"
fi

# A bundled archive that does not match its pin is refused.
printf '%s' 'tampered' >> "${TEST_TMP}/bp/dependencies/opencode-test.tar.gz"
if install_opencode "${TEST_TMP}/deps/2" "${TEST_TMP}/cache" "${TEST_TMP}/bp" \
    >/dev/null 2>&1; then
  fail "tampered opencode archive was installed"
fi

# So is a correctly pinned archive with more than one opencode in it.
unsafe_archive="${TEST_TMP}/unsafe-archive"
mkdir -p "${unsafe_archive}/nested"
cp "${good_archive}/opencode" "${unsafe_archive}/opencode"
cp "${good_archive}/opencode" "${unsafe_archive}/nested/opencode"
fake_buildpack "${TEST_TMP}/unsafe-bp" "${unsafe_archive}"
if install_opencode "${TEST_TMP}/deps/3" "${TEST_TMP}/cache" "${TEST_TMP}/unsafe-bp" \
    >/dev/null 2>&1; then
  fail "archive with unexpected contents was installed"
fi

echo "install-test: PASS"
