# Plan: migrate namespace `@genvid` → `@genvidtech`

Repo was transferred `genvid-holdings` → `GenvidTechnologies`; git remote already
points there. New npm scope `@genvidtech` is set up with OIDC (a `0.0.1` placeholder
is already published, so `1.2.4` is a clean higher version — no version bump).

Branch: `chore/migrate-namespace-genvidtech` off `main`. Version stays `1.2.4`.

## Verified corrections to the original request
- CI recipe repo's real new name is **`GenvidTechnologies/public-github-actions`**
  (not "github-actions-public"); the old `genvid-holdings/genvid-public-ci` redirects
  there and it contains `node-gate.yml`.
- `@genvidtech/cordova-plugin-eos` already exists on npm at `0.0.1`.

## A. npm scope `@genvid/` → `@genvidtech/`
- `package.json` name
- `package-lock.json` name (root, x2) — sync via `npm install --package-lock-only`
- `README.md` badge + `cordova plugin add` line

## B. Packed tgz filename ripple → `genvidtech-cordova-plugin-eos-*.tgz`
- `demo/config.xml` plugin `.tgz` pin
- `scripts/version-guard.js` pin regex + comment
- `README.md`, `CLAUDE.md` tgz mentions

## C. GitHub org `genvid-holdings` → `GenvidTechnologies`
- `plugin.xml` repo/issue URLs
- `package.json` repository/homepage/bugs URLs
- `.vscode/settings.json` circleci project selection
- `types/index.d.ts` Project URL
- `scripts/version-guard.js` attribution comment

## D. CI recipe repo → `GenvidTechnologies/public-github-actions`
- `.github/workflows/ci.yml`, `publish.yml` `uses:` line
- `CLAUDE.md` prose references

## Not changing (verified)
- `com.genvidtech.*` Android package / iOS bundle id — already `genvidtech`.
- `CONVENTIONS.md` / `docs/TOC.md` "Genvid plugin" — dev-tooling plugin, unrelated.
- `tests/package.json` name — unscoped `cordova-plugin-eos-tests`.

## Out of scope (ops follow-up)
- Deprecating/redirecting old `@genvid/cordova-plugin-eos` on npm.
- Confirming npm trusted-publisher config for `@genvidtech`.

## Gate
`npm run lint` + `npm run version-guard` + `tsc --noEmit`, then code-review.
