# Wattsup brand specification

Wattsup is a native macOS menu bar utility for live MacBook power telemetry. Lead with the signal and the power path from Adapter to Mac to Battery. The voice is friendly in headlines and precise in measurements, labels, and battery states.

## App icon

The three directions are Conversation, a speech bubble with a current line, Rising signal, a waveform with the lift of a greeting, and Plug with a smile, a USB-C-inspired connector with a curved detail. Rising signal is the selected direction. The refined trace uses a heavier stroke, a softer trough, and a short level exit. The light citron trace remains visible at 16 px, where the finest rim detail falls away.

- Artboard is 1024 × 1024 px, sRGB with a transparent exterior. The squircle runs from (62, 62) to (962, 962) before the 6 px rim. The floor shadow is offset 11 px downward.
- Tile gradient stops are #343768, #24274F and #1D2043. Rim stops are #565887, #393D68 and #24274E. The trace is #D8F98B. Use the supplied SVG for the exact contour and finish.
- The symbol is drawn at 11 units thick with round caps and joins on a nominal 100-unit construction grid. The app icon scales it by 6.4 and translates it by (175, 157) on the master canvas. Its 70.4 px master stroke renders to about 1.1 px at 16 px.
- Native-size proof shows 1024, 128, 32 and 16 px side by side. The 32 and 16 px nearest-neighbor details show the actual raster pixels. Open the proof at 100% to inspect the original sizes. The kit also includes 256 and 512 px exports.

Reference centerline for redrawing the symbol

```svg
M 12 56 H 26 C 33 56 36 51 40 43 L 45 34
C 48 28 54 28 57 35 L 68 61
C 71 68 76 69 81 63 L 85 58
C 88 55 90 54 94 54
```

## Menu bar templates

All coordinates are in points from the artboard’s top-left, with x increasing right and y increasing down. Each file is 18 × 18 pt, using pure black #000000 and transparent negative space. PNGs are 18 × 18, 36 × 36 and 54 × 54 px at 1×, 2× and 3×. SVGs preserve the construction curves. Mark the image as a template in AppKit and set its logical size to 18 × 18 pt.

- Common battery case spans x=1 to 15 and y=4 to 14 with 2.5 pt outer corner radii. The transparent opening spans x=2.5 to 13.5 and y=5.5 to 12.5 with 1 pt corners, yielding a 1.5 pt shell. The right terminal spans x=15 to 17 and y=7 to 11 with 1 pt outer-right corners.
- The optical center of the case is (8, 9). The terminal extends to the right into the remaining canvas. Keep the full transparent artboard in the image set.

| State | Interior geometry |
|---|---|
| Charging | Up arrow from x=4.5 to 11.5 and y=5.9 to 12.1. Tip at (8, 5.9). Head base y=8.8. Stem x=6.9 to 9.1 to y=12.1. |
| Discharging | Down arrow reflected across y=9. Tip at (8, 12.1). Head base y=9.2. Stem x=6.9 to 9.1 from y=5.9. |
| Fully charged on AC | Solid 9 × 5 pt rounded rectangle at (3.5, 6.5). Radius 0.65 pt. |
| Plugged in, held | Two 1.6 × 4.8 pt bars at (5.6, 6.6) and (8.8, 6.6). Radius 0.35 pt. Gap 1.6 pt. |
| No battery | Filled cross centered on (8, 8.8), within x=5.25 to 10.75 and y=6.05 to 11.55. Diagonal bands are approximately 1.56 pt wide. |

Use state names as accessibility labels, including “Plugged in, charging on hold” and “No battery detected.” Map the full and held states from actual charge status, for example when power is present and optimized charging pauses the battery below its target.

## Logos and spacing

Use Inter Variable at optical size 14. Set **Watt** at weight 750 and **sup** at weight 560. Track at −0.025 em throughout with an additional −0.055 em adjustment for the W and a pair (−1.25 pt tracking and −2.75 pt extra on the W and a pair at 50 pt). The SVG wordmark is outlined. Use the capitalization shown.

| Lockup | Composition | Minimum visible width |
|---|---|---:|
| Symbol | Trace alone | 16 px |
| Horizontal | Trace to the left of the wordmark. Master visible gap is about 17.6 units at 50-unit type. | 100 px |
| Stacked | Trace centered above the wordmark. Master visible gap is about 9.6 units at 50-unit type. | 88 px |

Light mode uses #4835A5 for the trace and “Watt,” and #171A2C for “sup.” Dark uses #C5B8FF and #F3F5FE respectively. One-color artwork uses #171A2C or reversed #FFFFFF throughout. Leave at least 2X on every side of the visible lockup, where X is the rendered trace stroke width. Keep surrounding artwork at least 8% of the tile width from the visible app icon tile. Preserve proportions, trace weight, wordmark spacing, and tile colors. Prefer a quiet area of the wallpaper behind the app icon.

## Color system

All values are sRGB. The ratios are the minimum for each token against the two listed surfaces in its matching mode. Every foreground token clears WCAG AA’s 4.5:1 threshold for normal text with these pairings. The descriptive labels, marker silhouettes and line patterns identify the data in grayscale and with color vision deficiencies. Color remains an additional cue.

| Role | Light | Dark | Min light / dark | Data identifier |
|---|---|---|---|---|
| Brand primary, Iris | #4835A5 | #C5B8FF | 8.34 / 8.82 | |
| Brand secondary, Citron | #3D6418 | #D8F98B | 6.40 / 13.48 | |
| Input power | #254EAF | #8EB1FF | 6.97 / 7.46 | Circle and solid line |
| System load | #65439B | #CFB2FF | 6.86 / 8.66 | Square and 8/4 dash |
| Battery charging | #00634F | #7CE1B5 | 6.70 / 10.04 | Up triangle and 1/5 dotted stroke |
| Battery draining | #8F3768 | #FFA9D5 | 6.66 / 8.98 | Down triangle and 7/4/1/4 dash-dot |
| Warning | #855006 | #FFCA75 | 6.17 / 10.54 | Diamond and 13/5 long dash |
| Primary text | #171A2C | #F3F5FE | 15.91 / 14.58 | |
| Secondary text | #4D5770 | #B2BAD4 | 6.67 / 8.21 | |
| Canvas | #F4F6FB | #111427 | | Base surface |
| Elevated | #FFFFFF | #1C2138 | | Popovers and cards |

Dash values are alternating lengths and gaps in points at the 2 pt chart-stroke reference. Keep a visible legend or directly label the traces. Pair thermal and battery-health warnings with a diamond and explicit status such as “High temperature” or “Battery service recommended.”

## macOS UI typography

| Role | Typeface and weight | Size / line height | Tracking |
|---|---|---|---|
| Large stat | SF Pro Display Semibold, tabular figures | 36 / 40 pt | −0.72 pt |
| Section title | SF Pro Text Semibold | 15 / 20 pt | −0.15 pt |
| Label | SF Pro Text Medium | 12 / 16 pt | 0 |
| Numeric readout | SF Mono Medium, tabular figures | 13 / 18 pt | 0 |

Use the native system font with tabular digits for the large stat and the native monospaced system font for readouts. Align changing values by the right edge or decimal column. Keep units in secondary text with a space after the value, as in “67.4 W,” “20.0 V,” and “3.37 A.” Use an explicit sign for battery direction, for example “+42.6 W” to charge and “−12.3 W” to drain. The typography board uses Inter and DejaVu Sans Mono for its specimen. The table specifies the native macOS UI fonts.

## Social assets and voice

GitHub social preview is 1280 × 640 px. The README banner is 1600 × 400 px. Both show the app icon, wordmark, primary tagline, and a stylized Adapter → Mac → Battery flow. In live UI, use arrows to indicate measured direction, including Battery → Mac during discharge.

1. **Charging demystified.** (primary since the charger and battery icon; as a title, drop the period: "Wattsup: Charging demystified")
2. See watts up with your Mac.
3. Wattsup with your battery?
4. See every watt your Mac moves.
5. Know watts coming and going.
6. Watts in. Watts out.

## References

- [W3C WCAG 2.2 minimum contrast](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum)
- [W3C WCAG 2.2 use of color](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color)
- [Apple AppKit template images](https://developer.apple.com/documentation/appkit/nsimage/istemplate)
