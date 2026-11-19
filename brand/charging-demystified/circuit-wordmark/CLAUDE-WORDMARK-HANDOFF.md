# Wattsup circuit wordmark

This folder pairs the purple charger and red battery icon with an outlined circuit-style wordmark. The W starts at a plated pad. The two t's share a crossbar that ends at a red pad. All files have transparent backgrounds. SVGs contain the letter outlines and need no fonts.

## Which asset to use

- Site hero or navigation with adjacent text: use the standalone circuit wordmark or the app icon lockup, with alt text “Wattsup.” Use the dark asset on the current dark site and the white asset on light surfaces.
- Site hero tagline: use real HTML text, “Charging demystified.” Style it in CSS and preserve the existing H1, “Live power telemetry for your Mac.” Display the wordmark at 120 CSS px or larger.
- Static artwork: use the circuit tagline lockup, which already includes **Charging demystified.** underneath. The one-color edition is also available.
- To replace the header and footer lockup on the current site, copy Wattsup-Circuit-App-Lockup-dark.svg to site/logo-dark.svg. The site sets the displayed header and footer height in CSS. Update explicit width and height attributes to match the new SVG aspect ratio where needed.
- Follow the app packaging and Pages instructions in Wattsup-Charging-Demystified/CLAUDE-HANDOFF.md for the selected icon and web graphics.

## Prompt for Claude

Use this approved circuit wordmark and charger icon in goriparthi/wattsup. Integrate the wordmark on the existing marketing site and set **Charging demystified.** as responsive HTML text. Follow the icon handoff for the macOS bundle, favicon, and touch icon. Preserve the existing product headline and site content. Validate the assets in the app and on GitHub Pages.
