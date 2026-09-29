# Security policy

## Supported versions

Security fixes go into the latest minor release of this buildpack and the opencode
version it pins.

| Component | Supported |
| --- | --- |
| Buildpack 1.0.x | Yes |
| OpenCode 1.18.x bundled here | Yes |
| Earlier versions | No |

## Reporting a vulnerability

Don't open a public issue with exploit details, credentials, internal routes or
customer information. Use GitHub's private security-advisory reporting for this
repository. If that isn't enabled, contact the maintainers privately and ask for
a secure channel.

Include the affected version, the impact, a minimal reproduction, and whether the
issue is in this buildpack or in upstream opencode.

## Security posture

- Dependencies are fetched over HTTPS only and pinned by SHA-256, both when
  downloaded and when taken from the cache or a cached release.
- `config/dependencies.json` records a security floor for opencode (1.18.22,
  which fixes GHSA-632h-h47v-g4x4) and the advisories it fixes.
  `make dependencies` fails if the pinned opencode is below that floor.
- OpenCode archives are checked for exactly one `opencode` entry and no absolute
  or parent-directory paths before extraction.
- The runtime profile sets `OPENCODE_DISABLE_AUTOUPDATE=1`, so opencode cannot
  replace the verified binary with a download of its own.
- Cached releases are per-architecture and ship with a CycloneDX SBOM.
- The buildpack reads no service bindings and writes no credentials into the
  droplet.

### Upstream opencode dependencies

CI does not audit opencode's own dependencies. opencode is a Bun-compiled
TypeScript binary, and its only lockfile is the monorepo's root `bun.lock`, which
also covers the desktop app, web console, and SDKs. None of those is in the CLI
binary, so a scan of that lockfile can't tell what actually ships. For 1.18.33,
OSV reported HIGH or CRITICAL advisories in 35 of its 3,244 packages, mostly in
`electron`, `astro`, and `wrangler`. Trivy 0.74 can't parse the lockfile at all
and skips it without an error.

Instead, the buildpack relies on the pinned version, its security floor, opencode's
own advisories, and the weekly upstream release watch.
