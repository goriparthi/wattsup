# Wattsup user guide

What every number means and how each feature decides what to tell you.

## Menu bar

The readout sits in an outlined capsule, colored by meaning, with thin dividers between
readings. Hover any number for a tooltip naming it. Click it for the popover.

Out of the box it shows **From the wall | Charger load | Mac uses | Battery percent**. On battery
the two charger readings drop out, leaving Mac use and percent.

Settings (gear menu, then Settings) lists all 17 readings. Tick the ones to show; use the arrows to
reorder any of them. Choose one line or two stacked rows, colors on or off, the outline, and the
icon (power bolt and plug, battery state, or none).

| Reading | Plugged in | On battery |
| --- | --- | --- |
| Power in or out | Watts the charger delivers into the Mac | Watts the Mac draws from the battery |
| Voltage, Current | Charger input bus | Battery pack |
| Mac uses | Charger input minus what the battery takes, so the flow always balances | What the battery supplies |
| Battery power | Plus while charging | Minus while draining |
| From the wall | Charger input plus its conversion loss | Hidden |
| Charger loss | Watts the charger turns into heat | Hidden |
| Charger load | Share of the active power profile's limit in use | Hidden |
| Battery percent, Time, Temperature, Health | | |
| Energy mode | Shown only when Low or High Power is on | |
| Powering accessories | Power macOS allocated to USB devices | |
| Chip temperature | Average of the CPU sensors | |
| Fan speed | The faster fan; hidden on fanless Macs | |
| Power graph | The last 60 seconds of power in or out, drawn in the capsule | |

Colors: charger input blue, Mac use purple, charging green, draining pink, warnings amber.

## Popover

- **Battery tank**: the liquid level is the charge. Bubbles rise while charging and drops fall while
  draining, faster at higher watts.
- **Power flow**: Charger, Mac and Battery nodes joined by pipes. Pipe thickness follows the watts
  and particles flow in the real direction, Battery to Mac when unplugged. Accessories branch off
  the Mac.
- **Charger check** verdict, a five minute chart, then grouped details: Charger, Battery, Mac.

With macOS Reduce Motion on, the animations hold still and arrows show direction instead.

## Charger check

Compares what the Mac would draw (its own load plus the charge power the battery is requesting)
with what the charger's active Power Delivery profile can supply. After about 30 seconds on a
charger it says one of:

- **Charger is the bottleneck**: the charger runs at 90% or more of its limit while the Mac wants
  more. It suggests the smallest common size with 10% headroom.
- **Charger can't keep up**: the battery drains while plugged in.
- **Charger has headroom**: it keeps up, and may note that a lighter charger would also do.

Advisories appear under the verdict:

- **Cable or charger?** A charger only offers more than 3 A after detecting a 5 A cable, so a
  100 W charger on a basic cable looks exactly like a 60 W charger. When every profile stops at
  3 A, Wattsup says **check the cable**: if your charger is rated above 60 W, a 5 A cable rated
  100 W or 240 W unlocks the rest. If a charger that reports its own name (Apple's do) was seen
  delivering more on another cable, it says plainly that **the cable is the bottleneck**.
- The Mac picked a lower profile than the charger offers, or current is capped below the profile.
- macOS paused or slowed charging, with its raw reason code (Apple does not document them).

## Charger efficiency

Delivered watts divided by wall watts, using macOS's own loss estimate. Graded **Excellent** at 94%
or more (typical of good GaN chargers), **Good** at 90%, **Fair** at 85%, **Poor** below. Not rated
under 10 W, where every charger is least efficient. Shown in the popover and the dashboard, and
averaged per charger in Chargers you've used.

## Charger report card

Graded from measured samples only; each check stays ungraded until its load has happened, and
the overall grade is the weakest check.

| Check | How it is measured |
| --- | --- |
| Voltage under load | Sag below the negotiated voltage while the charger is above 30% of its limit |
| Cable resistance | Slope of input voltage against current as the load varies, which separates the cable from the charger's own voltage tolerance |
| Delivers its rating | How close it got to its limit when the Mac asked for more |
| Connection | Unplug and replug of the same charger within 10 seconds |
| Heat | Whether macOS slowed charging because of temperature |

The first 20 seconds after plugging in are a negotiation phase and are never judged.

### Charger and cable test

Cable resistance needs the current to change, which everyday use may not do. On the dashboard's
Charger card, click **Test now**: Wattsup measures at rest for 5 seconds, loads every CPU core for
10, lets it settle for 5, samples twice a second, and grades the result on the spot. It stops if
you unplug, switch chargers, cancel, or the hottest core reaches 95 °C. A charger already at its
limit cannot swing further, so the cable stays ungraded and the result says so.

## History

The last hour is kept at full detail in memory. One averaged point per minute is saved to disk
for 30 days, so the dashboard charts reach back 24 hours or 7 days across restarts.

## Charger library

Every charger you use is kept in a local file and ranked. Sort by Overall, Power, Efficiency,
Quality or Recently used. Overall weighs the power a charger can deliver (40%), its average
efficiency (30%) and its report card (30%); anything not measured yet is left out rather than
counted as zero. Use the pencil to name a charger; the name shows in the popover and the Charger
card, and is never written to the log. The same brick on a different cable negotiates differently,
so it gets its own entry, which also ranks your cables. Use the ⋯ menu, Same charger as, to combine
those entries into one brick ranked on its best cable; Separate undoes it. Apple chargers report a
serial number, so identical Apple bricks stay apart; third party chargers do not, so identical
units of one model share an entry. Last seen shows the exact local time.

**Which charger to pack.** Above the list, Wattsup takes what your Mac typically draws on a
charger (the median minute) and when busy (the 95th percentile), then names the smallest charger
in your library whose limit covers the busy figure, plus the fastest one. It needs an hour of
history on a charger first.

## Charging receipts

Each time you charge for 2 minutes or more, Wattsup writes a receipt: the charger, start and end
percent, watt hours added and drawn from the wall, average and peak watts, minutes to 80%, and the
share of the time the charger was the bottleneck. Gaps of over a minute while Wattsup was not
running are not counted. The dashboard lists recent receipts; Settings can also send one as a
notification when you unplug (off by default).

## Battery care

From Wattsup's own 30 day history: hours plugged in above 95%, hours at 40 °C or hotter, how often
the battery ran below 10%, and cycles per week, with plain advice. Weekly figures appear only once
there is a full day of history, so a few hours are never stretched into a weekly habit.

## Powering accessories

USB devices the Mac is powering, such as an iPhone or an AirPods case, with the power macOS
allocated to each (for example, iPhone up to 12 W). These are ceilings, not live readings; whatever
they actually draw is already part of Mac uses.

## Energy mode

Shows Low Power, Automatic, or High Power (only on Macs that offer it) for battery and charger, and
switches it. Changing it asks for an administrator password because macOS requires one.

## Dashboard

Everything above in full, plus history charts (power, volts and amps, charge and temperature) over
5, 15 or 60 minutes, every Power Delivery profile the charger offers, battery capacity, cycles,
per cell voltages and imbalance, and the charger log.

## Privacy

Readings never leave the Mac. The only network request is a daily check of GitHub releases for an
update. It is on by default and can be turned off from the gear menu (Check for Updates Daily) or
Settings. An update installs only after you agree, and only if Apple notarized it. Logs stay in `~/Library/Logs/Wattsup`.

## The built in battery icon

Wattsup can replace it. Settings, Menu bar space, opens the macOS Menu Bar settings where Battery
can be switched off. Command dragging the icon out of the menu bar also works.
