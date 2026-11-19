# Wattsup

Live power telemetry for your MacBook, in the menu bar. Watts, volts and amps at a glance, a
dashboard far deeper than the battery settings, and a charger check that tells you whether the
brick you plugged in is holding your Mac back.

Site: https://goriparthi.github.io/wattsup/

## What it shows

- **Menu bar**: pick any of power, voltage, current, battery power, percent, time to full or
  empty, temperature and charger load. Plugged in, power, volts and amps are the charger input; on
  battery they are the pack.
- **Popover**: live flow from charger to Mac to battery, the charger verdict, a 5 minute chart.
- **Dashboard**: power, voltage, current, charge and temperature over time; every USB-C Power
  Delivery profile the charger offers and which one is in use; live input, conversion loss and
  wall draw; battery health, cycles, per cell voltages, the current the battery is requesting,
  and why charging is slow or paused.
- **Charger check**: compares what the Mac would draw (system load plus the battery's requested
  charge power) with what the charger's active profile can deliver. It flags a pegged charger and a
  battery that drains while plugged in, suggests a size that would remove the bottleneck, and
  remembers every charger you use with its peak load.

Everything comes from the `AppleSmartBattery` IOKit entry, read locally without admin rights.
No network, no account, no tracking.

## Requirements

macOS 14 or later on an Apple silicon MacBook. Xcode for building and testing.

## Run it locally

```sh
make run        # debug build, opens the dashboard
make test       # unit tests
make install    # signed release build into ~/Applications, then launches it
.build/debug/wattsup --snapshot   # one reading as text
```

`make ci` runs exactly what GitHub Actions runs.

## Layout

| Path | What lives there |
| --- | --- |
| `Sources/WattsupCore` | Pure parsing and analysis: registry parsing, units, history, charger verdicts, charger log. No IOKit or AppKit, fully unit tested. |
| `Sources/wattsup` | The app: IOKit reader, monitor, status item, popover, dashboard. |
| `Tests/WattsupCoreTests` | Tests built from registry readings captured on a real MacBook. |
| `scripts/` | Build, bundle, sign, install, CI. The Makefile only indexes these. |
| `site/` | The marketing page, deployed to GitHub Pages on push to `main`. |

## Why the numbers can be trusted

The charger verdict uses only measured values: the active Power Delivery profile is the
ceiling, the battery's own requested voltage and current give the demand. Reason codes for slow
or paused charging are shown raw because Apple does not document them.

## Signing

`make bundle` signs with a Developer ID Application certificate when the keychain has one, and
ad-hoc otherwise. Notarized releases use a `notarytool` keychain profile.

## License

MIT
