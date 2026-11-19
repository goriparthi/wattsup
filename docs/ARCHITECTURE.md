# Architecture

## Targets

| Target | Role |
| --- | --- |
| `WattsupCore` | Pure logic: registry parsing, units, history, charger verdicts, efficiency, charger log, menu bar metrics, energy mode parsing, peripherals, log file, version ordering. No IOKit, AppKit or SwiftUI, so all of it is unit tested. |
| `wattsup` | The app: reads IOKit and pmset, owns the status item, popover, dashboard and settings, the updater and diagnostics. |
| `WattsupCoreTests` | Tests built from registry readings captured on a real MacBook. |

## Data sources

| Source | What it gives | Read by |
| --- | --- | --- |
| `AppleSmartBattery` IOKit entry | Charge, voltage, current, capacities, cycles, temperature, cell voltages, charger details and Power Delivery profiles, power telemetry (input, system load, adapter loss), charger request and reason codes | `SmartBattery.read`, parsed by `PowerSnapshot(registry:)` |
| `IOUSBHostDevice` entries | Name and `UsbPowerSinkAllocation` of powered USB devices | `USBPeripherals.read`, parsed by `Peripheral(registry:)` |
| `pmset -g custom` | Energy mode per power source | `EnergyModeController`, parsed by `EnergyModes.parse` |
| GitHub releases API | Newer version and its DMG | `Updates.check` |

None of these need admin rights. Changing energy mode does, through the standard prompt.

## Flow of a reading

1. `PowerMonitor` polls every 2 s, and immediately on IOKit power source notifications.
2. The registry dictionary becomes an immutable `PowerSnapshot`; energy mode and peripherals
   (scanned every third tick) are attached.
3. The snapshot joins `PowerHistory` (one hour), feeds `ChargerAssessment`, and folds into the
   persisted `ChargerLog` (`~/Library/Application Support/Wattsup/chargers.json`).
4. Transitions are logged; the status item is redrawn; SwiftUI views observe the monitor.

## Decisions worth knowing

- **Never guess a number.** Charger advice uses measured values only, undocumented reason codes
  are shown raw, and accessory power is labeled as an allocation.
- **On battery the pack is the only source.** Mac power equals battery output, and a charging
  current that lingers right after unplugging is treated as stale.
- **Health uses nominal capacity**, which is steadier than the raw full charge capacity.
- **The status item is one drawn image** (capsule, icon, readings, dividers), with per reading
  tooltip regions rebuilt only when the layout changes.
- **Animations accumulate phase** (`AnimationClock`), so a change in watts changes the speed of
  motion instead of making particles jump.
- **Colors come only from brand tokens** in `Brand.swift`, through `Theme`.

## Updater

Checks daily (can be turned off) and on demand. Only https downloads from GitHub hosts are
accepted. The DMG is copied out, and the copy must pass Gatekeeper, carry the pinned bundle id and
Developer ID team as a code signing requirement, and report exactly the advertised version, which
must be newer. A detached helper swaps the bundle after the app quits and relaunches it.
