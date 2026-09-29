#!/usr/bin/env bash
# The runtime environment: the opencode binary's location, and that it stays put.

setup_environment() {
    local deps_dir=$1
    local build_dir=$2
    local index=$3
    local profile_script="${build_dir}/.profile.d/opencode-env.sh"

    mkdir -p "${build_dir}/.profile.d"
    {
        printf '%s\n' '# OpenCode supply buildpack runtime environment'
        # These variables intentionally expand when Cloud Foundry sources the profile.
        # shellcheck disable=SC2016
        printf 'export PATH="$DEPS_DIR/%s/bin:$PATH"\n' "${index}"
        # shellcheck disable=SC2016
        printf 'export OPENCODE_CLI_PATH="$DEPS_DIR/%s/bin/opencode"\n' "${index}"
        # opencode updates itself by default, which would swap the SHA-256-pinned
        # binary for an unverified one at runtime.
        printf '%s\n' 'export OPENCODE_DISABLE_AUTOUPDATE=1'
    } > "${profile_script}"
    chmod 0644 "${profile_script}"

    export PATH="${deps_dir}/bin:${PATH}"
    export OPENCODE_CLI_PATH="${deps_dir}/bin/opencode"
    export OPENCODE_DISABLE_AUTOUPDATE=1
}

# The multi-buildpack convention: a supply buildpack describes what it supplied
# in <deps>/<index>/config.yml for the buildpacks that follow it.
create_config_file() {
    local deps_dir=$1
    local bp_dir=$2
    local config_file="${deps_dir}/config.yml"
    local version="${OPENCODE_RESOLVED_VERSION:-$(dependency_version "${bp_dir}/config/dependencies.json" opencode)}"

    cat > "${config_file}" <<EOF
---
name: opencode-supply-buildpack
config:
  version: ${version}
  cli_path: ${deps_dir}/bin/opencode
EOF
    chmod 0644 "${config_file}"
}
