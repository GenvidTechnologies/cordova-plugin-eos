---
okf_version: "0.2"
---

# Wiki Index

This is the wiki's table of contents — every page under `wiki/`,
grouped under section headings, one line each. `/gvt-wiki:maintain-wiki`
keeps this list current: a new page is added here when it's created, and
`lint` flags any page listed in **no** index — here, or in a
subdirectory's own `index.md`. Each entry's description is the linked
page's frontmatter `description`, so the index and the page can't drift.
See `wiki/schema.md` for the page format and maintenance rules.

Genvid plugin skills also read this index to find the project's docs: it is
the location that gvt-dev resolves for `docs/TOC.md`.

## Project context

These files sit at the repository root, outside the wiki bundle, so they are
named here rather than linked:

* `CLAUDE.md` - architecture overview, build/SDK/demo workflows, platform specifics.
* `CONVENTIONS.md` - genvid plugin convention contract for this repo.
* `README.md` - file layout and build/run instructions.

## Process

* [Issue Triage Conventions](issue-triage.md) - Issue triage conventions (labels, duplicates, dependencies, mutation recipes) for /gvt-dev:triage-issues.

## Schema

* [Wiki Maintenance Schema](schema.md) - The maintenance rules for this wiki — page format, create-vs-update lifecycle, raw/ immutability, staleness policy and the verb contract.
