# Logs and crash reports

## Where things live

| Path | Contents |
| --- | --- |
| `~/Library/Logs/Wattsup/wattsup.log` | Current log, one UTC timestamped line per event. Rotates at 1 MB, keeping `.1` to `.3`. |
| `~/Library/Logs/Wattsup/Crashes/` | macOS crash reports for Wattsup, copied here on the launch after a crash. |
| Unified log | The same entries under subsystem `com.goriparthi.wattsup`. |

Nothing here is sent anywhere.

## What gets logged

Launch (version, Mac model, macOS), clean quits, charger connect and disconnect, each new charger
with its negotiated profile, a likely cable cap, state changes, charger verdicts, accessories
appearing or leaving, energy mode changes, update checks and installs, and every error.

## Crash capture

Launch writes a `running` marker that only a clean quit removes, including a plain `kill`. If the
marker is still there at the next launch, the previous run crashed: that is logged, and any macOS
crash report for Wattsup written since then is copied into `Crashes/`. Uncaught Objective C
exceptions are written synchronously with their stack. A force quit or `kill -9` leaves no crash
report, and the log says so.

## Getting a report

- Gear menu, **Reveal Logs in Finder**.
- Terminal: `~/Applications/Wattsup.app/Contents/MacOS/wattsup --diagnostics` prints the log folder,
  saved crash reports, and the last 60 log lines.
- Unified log: `log show --last 1h --predicate 'subsystem == "com.goriparthi.wattsup"'`.

To read a crash report, open the `.ips` in Console, or look at the triggered thread's frames; the
top Wattsup frame names the file and line.
