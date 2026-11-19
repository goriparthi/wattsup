# Wattsup icon handoff

Use the purple wall charger and red battery with the tagline **Charging demystified.** The editable masters in SVG/ contain the exact vector paths and color values. Reuse those paths for new exports.

| Mode | Tile | Charger and lead | Battery |
|---|---|---|---|
| Dark | #272728 | #D677E1 | #FF595F |
| White | #FAFAFA | #932A99 | #EA2D23 |

The 1024 × 1024 artboard has a transparent exterior. The charger sits upper left and connects to the lower-right battery through one rounded bend. Keep the tile and marks flat with rounded geometry. Use the symbol-only SVGs for applications where a tile is unnecessary.

## macOS

1. For the existing shell bundle in goriparthi/wattsup, copy macOS/dark/Wattsup.icns to Resources/Wattsup.icns. The repository's bundle script copies it into the assembled application.
2. For a target using an Xcode asset catalog, use macOS/dark/AppIcon.appiconset in that target's asset catalog.
3. The matching macOS/white/ assets are an alternate set. Select one for the bundle. Both contain standard and Retina entries.
4. On macOS, build and check Finder, the Dock, and app switching before shipping a release. Keep the existing monochrome menu bar templates.

## GitHub Pages

The live site is https://goriparthi.github.io/wattsup/. Its source is site/ in goriparthi/wattsup.

1. Copy these files from Marketing/ to site/: app-icon-dark.svg, app-icon-white.svg, logo-dark.svg, favicon.svg, app-icon-256.png, and og.png.
2. The existing header, footer, favicon, Apple touch icon and Open Graph image use those filenames. Render app-icon-dark.svg above the hero title and add the tagline **Charging demystified.** above the existing headline **Live power telemetry for your Mac**.
3. Update the social title and alt copy to **Wattsup: Charging demystified.** The provided og.png is 1280 × 640. The optional readme-banner.png is 1600 × 400 for the GitHub README.
4. Preserve the site's existing dark design, download links and screenshots. Test mobile and desktop. Merge the site/ changes into main to trigger the existing GitHub Pages workflow, then verify the live URL.

## Prompt to paste into Claude

Implement this approved Wattsup charger-to-battery icon in the goriparthi/wattsup repo. Use the provided SVG and packaged icons directly. Adopt the dark macOS resource, retain the white variant, and update the existing GitHub Pages site with the approved icon and **Charging demystified.** tagline. Follow the paths above and verify the bundle and deployment.
