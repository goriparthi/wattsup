# Wattsup

Personal project, modeled on `../redline`. Read `README.md` for layout and commands.

## Conventions

- **No Jira ticket and no ticket-prefixed branch.** Plain short commit subjects, e.g.
  `Charger check: flag a cable capped below the profile current`.
- No em or en dashes anywhere; `make ci` fails on them.
- Code comments and file headers: two lines maximum.
- Testable logic goes in `WattsupCore`, which has no IOKit, AppKit or SwiftUI. The app target
  only reads the registry and draws.
- Never guess a number the user reads as fact. Undocumented reason codes are shown raw, and
  charger advice comes from measured values only, never a model lookup table.
- Colors come from `Theme` in `Sources/wattsup/Components.swift`; it is a placeholder until the
  brand kit lands.

## Checks

`make test` for the unit suite, `make ci` for everything CI runs. Verify UI changes by running
the app (`make run`) and looking at it, not by reading the code.

## Deploying

The site deploys from `site/` on push to `main`. App releases are not set up yet; when they are,
follow `../redline/docs/DEPLOY.md` and confirm before publishing.
