#!/usr/bin/env bash
# Dependency installation with publisher-pinned SHA-256 verification.

host_architecture() {
    case "$(uname -m)" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *)
            echo "       ERROR: Unsupported architecture: $(uname -m)" >&2
            return 1
            ;;
    esac
}

sha256_file() {
    local file=$1
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${file}" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${file}" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "${file}" | awk '{print $NF}'
    else
        echo "       ERROR: sha256sum, shasum, or openssl is required" >&2
        return 1
    fi
}

verify_sha256() {
    local file=$1
    local expected=$2
    local actual

    [ -f "${file}" ] || {
        echo "       ERROR: Dependency not found: ${file}" >&2
        return 1
    }
    [[ "${expected}" =~ ^[a-f0-9]{64}$ ]] || {
        echo "       ERROR: Invalid expected SHA-256 for $(basename "${file}")" >&2
        return 1
    }
    actual=$(sha256_file "${file}") || return 1
    if [ "${actual}" != "${expected}" ]; then
        echo "       ERROR: SHA-256 mismatch for $(basename "${file}")" >&2
        echo "       Expected: ${expected}" >&2
        echo "       Actual:   ${actual}" >&2
        return 1
    fi
    echo "       Verified SHA-256 for $(basename "${file}")"
}

download_atomic() {
    local url=$1
    local destination=$2
    local expected_sha=$3
    local partial="${destination}.part"
    local retry_count=0

    [[ "${url}" == https://* ]] || {
        echo "       ERROR: Refusing non-HTTPS dependency URL" >&2
        return 1
    }
    rm -f "${partial}"
    while [ "${retry_count}" -lt 3 ]; do
        if curl --fail --silent --show-error --location \
            --connect-timeout 15 --max-time 300 \
            "${url}" --output "${partial}"; then
            if verify_sha256 "${partial}" "${expected_sha}"; then
                mv "${partial}" "${destination}"
                return 0
            fi
            rm -f "${partial}"
            return 1
        fi
        retry_count=$((retry_count + 1))
        echo "       Download failed; retry ${retry_count}/3" >&2
    done
    rm -f "${partial}"
    echo "       ERROR: Failed to download ${url}" >&2
    return 1
}

# jq reads config/dependencies.json, so its own pin cannot live there alone:
# scripts/check-dependencies.sh fails if this copy drifts from the manifest.
bootstrap_jq_metadata() {
    local arch=$1
    case "${arch}" in
        amd64)
            printf '%s\t%s\t%s\n' \
                "jq-linux-amd64" \
                "https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-amd64" \
                "b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f"
            ;;
        arm64)
            printf '%s\t%s\t%s\n' \
                "jq-linux-arm64" \
                "https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-arm64" \
                "8b85c817833814ddca00a144c33705546355afccf0cf39b188f3cdb48b852309"
            ;;
        *) return 1 ;;
    esac
}

install_jq() {
    local install_dir=$1
    local bp_dir=$2
    local cache_dir=$3
    local arch filename url expected src dst cache_file

    arch=$(host_architecture) || return 1
    mkdir -p "${install_dir}/bin" "${cache_dir}"

    IFS=$'\t' read -r filename url expected < <(bootstrap_jq_metadata "${arch}")
    src="${bp_dir}/dependencies/${filename}"
    cache_file="${cache_dir}/${filename}"
    dst="${install_dir}/bin/jq"

    if [ -f "${src}" ]; then
        verify_sha256 "${src}" "${expected}" || return 1
        cp "${src}" "${dst}"
    elif [ -f "${cache_file}" ]; then
        verify_sha256 "${cache_file}" "${expected}" || return 1
        cp "${cache_file}" "${dst}"
    else
        echo "       Downloading jq for ${arch}"
        download_atomic "${url}" "${cache_file}" "${expected}" || return 1
        cp "${cache_file}" "${dst}"
    fi
    chmod 0755 "${dst}"

    export PATH="${install_dir}/bin:${PATH}"
    "${dst}" --version >/dev/null
    echo "       Installed verified jq for ${arch}"
}

dependency_value() {
    local manifest=$1
    local dependency=$2
    local arch=$3
    local field=$4
    jq -er --arg dependency "${dependency}" --arg arch "${arch}" --arg field "${field}" \
        '.dependencies[$dependency].assets[$arch][$field]' "${manifest}"
}

dependency_version() {
    local manifest=$1
    local dependency=$2
    jq -er --arg dependency "${dependency}" '.dependencies[$dependency].version' "${manifest}"
}

install_opencode() {
    local install_dir=$1
    local cache_dir=$2
    local bp_dir=$3
    local manifest="${bp_dir}/config/dependencies.json"
    local arch version filename url expected archive cache_file bundled_archive custom_version

    arch=$(host_architecture) || return 1
    [ -f "${manifest}" ] || {
        echo "       ERROR: Dependency manifest not found: ${manifest}" >&2
        return 1
    }
    jq -e '.schemaVersion == 1' "${manifest}" >/dev/null || {
        echo "       ERROR: Unsupported dependency manifest" >&2
        return 1
    }

    version=$(dependency_version "${manifest}" opencode) || return 1
    filename=$(dependency_value "${manifest}" opencode "${arch}" filename) || return 1
    url=$(dependency_value "${manifest}" opencode "${arch}" url) || return 1
    expected=$(dependency_value "${manifest}" opencode "${arch}" sha256) || return 1

    custom_version="${OPENCODE_VERSION:-}"
    if [ -n "${custom_version}" ] && [ "${custom_version#v}" != "${version}" ]; then
        if [ -z "${OPENCODE_DOWNLOAD_URL:-}" ] || [ -z "${OPENCODE_SHA256:-}" ]; then
            echo "       ERROR: OPENCODE_VERSION=${custom_version} is not in the dependency manifest" >&2
            echo "       Supply both OPENCODE_DOWNLOAD_URL and OPENCODE_SHA256 for an explicit custom build" >&2
            return 1
        fi
        [[ "${OPENCODE_DOWNLOAD_URL}" == https://* ]] || {
            echo "       ERROR: OPENCODE_DOWNLOAD_URL must use HTTPS" >&2
            return 1
        }
        version="${custom_version#v}"
        filename="opencode-custom-${arch}.tar.gz"
        url="${OPENCODE_DOWNLOAD_URL}"
        expected="${OPENCODE_SHA256}"
        echo "       Using explicitly checksummed custom OpenCode ${version}"
    else
        echo "       Using manifest-pinned OpenCode ${version} for ${arch}"
    fi

    cache_file="${cache_dir}/opencode-${version}-${arch}.tar.gz"
    bundled_archive="${bp_dir}/dependencies/${filename}"

    if [ -f "${bundled_archive}" ]; then
        verify_sha256 "${bundled_archive}" "${expected}" || return 1
        archive="${bundled_archive}"
        echo "       Using verified bundled OpenCode archive"
    elif [ -f "${cache_file}" ]; then
        verify_sha256 "${cache_file}" "${expected}" || return 1
        archive="${cache_file}"
        echo "       Using verified cached OpenCode archive"
    else
        echo "       Downloading OpenCode ${version} from GitHub"
        download_atomic "${url}" "${cache_file}" "${expected}" || return 1
        archive="${cache_file}"
    fi

    mkdir -p "${install_dir}/bin"
    if ! tar tzf "${archive}" | awk '
        BEGIN { count = 0 }
        /(^|\/)opencode$/ { count++ }
        /^\// || /(^|\/)\.\.(\/|$)/ { unsafe = 1 }
        END { exit !(count == 1 && !unsafe) }
    '; then
        echo "       ERROR: OpenCode archive has unexpected or unsafe contents" >&2
        return 1
    fi
    tar xzf "${archive}" -C "${install_dir}/bin"
    chmod 0755 "${install_dir}/bin/opencode"

    if ! "${install_dir}/bin/opencode" --version >/dev/null 2>&1; then
        echo "       ERROR: OpenCode binary failed its version check" >&2
        return 1
    fi
    export OPENCODE_RESOLVED_VERSION="${version}"
    echo "       Installed OpenCode $("${install_dir}/bin/opencode" --version)"
}

get_opencode_version() {
    local install_dir=$1
    if [ -x "${install_dir}/bin/opencode" ]; then
        "${install_dir}/bin/opencode" --version 2>/dev/null || echo "unknown"
    else
        echo "not installed"
    fi
}

verify_installation() {
    local install_dir=$1
    [ -x "${install_dir}/bin/opencode" ] || {
        echo "       ERROR: OpenCode CLI verification failed" >&2
        return 1
    }
    "${install_dir}/bin/opencode" --version >/dev/null 2>&1 || {
        echo "       ERROR: OpenCode CLI cannot execute" >&2
        return 1
    }
    echo "       Installation verified"
}
