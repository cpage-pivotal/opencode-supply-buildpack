# OpenCode Supply Buildpack

A Cloud Foundry v2 **supply buildpack** that puts one checksum-verified
[opencode](https://github.com/anomalyco/opencode) binary in the droplet, exports
`OPENCODE_CLI_PATH`, and turns off opencode's self-update. That is everything it
does.

It is for applications built on [Spring AI ACP](https://github.com/cpage-pivotal/acp-spring),
such as `spring-ai-acp-chat`, whose OpenCode runtime adapter launches the binary
named by `OPENCODE_CLI_PATH` as `opencode acp`. Spring AI ACP configures the agent
itself: provider and model (including from a bound Tanzu AI Models service),
MCP servers, skills, and the `opencode.json` it points `OPENCODE_CONFIG` at. This
buildpack therefore writes no opencode configuration and reads no service
bindings.

- Buildpack: **1.0.0**
- OpenCode: **1.18.33**
- Architectures: Linux amd64 and arm64

## Usage

Name it before the final buildpack. A supply buildpack is never auto-detected.

```yaml
applications:
  - name: spring-ai-acp-chat
    path: target/spring-ai-acp-chat-1.0.0.jar
    buildpacks:
      - https://github.com/cpage-pivotal/opencode-supply-buildpack
      - java_buildpack_offline
    env:
      ACP_RUNTIME: opencode
```

At startup, `.profile.d/opencode-env.sh` sets:

| Variable | Value |
| --- | --- |
| `OPENCODE_CLI_PATH` | `$DEPS_DIR/<index>/bin/opencode` |
| `OPENCODE_DISABLE_AUTOUPDATE` | `1`, so the pinned binary is the one that runs |
| `PATH` | `$DEPS_DIR/<index>/bin` prepended (opencode and jq) |

## What staging does

1. Installs jq, pinned by SHA-256 in `lib/installer.sh`, to read the dependency
   manifest.
2. Installs the opencode release for the container's architecture from
   `config/dependencies.json`: HTTPS only, SHA-256 verified, and the `.tar.gz`
   must contain exactly one `opencode` and no absolute or `..` paths.
3. Writes the profile script and `<deps>/<index>/config.yml`, then runs
   `opencode --version`.

Archives are taken from the buildpack's own `dependencies/` directory (the
cached release), then the staging cache, then downloaded.

The pinned assets are upstream's glibc builds (`opencode-linux-x64.tar.gz`,
`opencode-linux-arm64.tar.gz`), which suit cflinuxfs4. The x64 build needs a CPU
with AVX2.

### An opencode that is not pinned

To stage an opencode version or build the manifest doesn't pin, set all three.
One example is upstream's `opencode-linux-x64-baseline.tar.gz`, which is for
CPUs without AVX2:

```yaml
env:
  OPENCODE_VERSION: 1.18.32
  OPENCODE_DOWNLOAD_URL: https://github.com/anomalyco/opencode/releases/download/v1.18.32/opencode-linux-x64-baseline.tar.gz
  OPENCODE_SHA256: <64 hex characters>
```

The override applies only when `OPENCODE_VERSION` (ignoring a leading `v`)
differs from the pinned version. If it matches, the pinned asset is installed and
the other two variables are ignored. To run a different build of the pinned
version, change its asset in a fork's `config/dependencies.json`.

## Releases

Pushing a `v*` tag builds an offline (cached) buildpack per architecture with
opencode and jq bundled, plus a CycloneDX SBOM and checksums:

```bash
cf create-buildpack opencode_supply_buildpack opencode_supply_buildpack-cached-v1.0.0-amd64.zip 99
```

## Development

```bash
make test        # bash -n, shellcheck, dependency metadata, tests/*-test.sh
make package     # online zip + validated SBOM in build/
make freshness   # compare pins with the latest upstream releases
```

To bump opencode, edit `config/dependencies.json` (version, `sourceCommit`,
`purl`, and both assets' URL and SHA-256) and the version in this README and
SECURITY.md. Take the SHA-256s from the release's asset digests
(`gh release view vX.Y.Z --repo anomalyco/opencode --json assets`). To bump jq,
change it in both `config/dependencies.json` and `bootstrap_jq_metadata` in
`lib/installer.sh`; `make dependencies` fails if they differ.
