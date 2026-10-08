# 07 - Display under a closed lid, and remote wake of a sleeping Mac

Research date: 2026-10-06. Read-only. No power setting was changed. No display was put to sleep.
Test Mac for local reads: Mac17,9 (14-inch MacBook Pro, Apple M5 Pro), macOS 26.7.1 (25G241), battery design capacity 6249 mAh (about 72 Wh), lid open, on AC during the research.

Evidence labels:

- **[P]** primary source: Apple open source (xnu, PowerManagement/powerd, IOKitUser), SDK headers, man pages, vendor documentation, or a read-only command on this Mac.
- **[P-log]** primary, observational: lines from `pmset -g log` on this Mac (7 days, 2026-09-29 to 2026-10-06). The lid state is not printed in that log. I infer it from lid events (see 1.1).
- **[C]** community report: READMEs, forum posts, reviews.
- **[I]** inference from primary sources. Not tested on hardware.
- **[U]** unconfirmed.

Source snapshot used: `apple-oss-distributions/PowerManagement` tag `PowerManagement-1846.0.25.0.1` (cloned to `src/PowerManagement`), `IOPMrootDomain.cpp` and `IOPMAutoWake.c` in `src/` (same files as note 02). Line numbers refer to those copies.

A read-only logger for the owner's tests is in `probe07/lidprobe` (source `probe07/lidprobe.swift`). It prints lid state, display state, backlight current, and battery watts. It changes nothing.

---

## 0. Short answer

**Feature 1 (dim the screen when the lid is closed): do not build it.**
macOS turns the built-in display off by itself when the lid closes, also when `SleepDisabled` keeps the Mac awake. The log of this Mac shows it. The display is not what uses the battery under a closed lid. The CPU is. One overnight run on this Mac (lid closed, awake, display off, about 10.5 hours) used 7 displayed battery points. A small, useful thing to build instead: an optional Low Power Mode switch for "lid closed on battery", plus one self-check line in the diagnostics ("display is off: yes").

**Feature 2 (a phone message wakes a sleeping Mac): not possible as asked. A near substitute is possible.**
No message from Claude Code Remote Control or Codex remote can wake a sleeping Mac. Both need a live outbound connection from the Mac, and both vendors say that sleep stops remote access. A third-party app cannot get a network wake on Apple silicon. Two designs give most of the value:

1. **"Stay reachable" (build first).** Do not sleep. Keep the Mac awake and idle with the lid closed for a time that the user chooses. Measured cost here: about 0.7 to 1.0 percent per hour, against about 0.3 to 0.4 percent per hour asleep. This uses only what the app has today.
2. **"Check-in wakes" (experiment second).** The root helper schedules a wake each N minutes. The helper holds the Mac for 20 to 30 seconds with `SleepDisabled`. The agent's remote connection reconnects and pulls the pending message. This rests on three behaviours that I could not prove without a hardware test. The owner must run the test in section 2.6 before any code is written.

---

# FEATURE 1 - display under a closed lid

## 1.1 What macOS does today when the lid closes and the Mac stays awake

**The built-in display goes off. macOS does it. The app does not need to.**

Mechanism [P]:

- The kernel receives the lid event, sets `clamshellClosed = true`, and tells its clients (`IOPMrootDomain.cpp:8755-8778`, `sendClientClamshellNotification`). It then evaluates clamshell sleep. `SleepDisabled` stops the sleep, not the notification.
- `powerd` gets the new state and forwards it to WindowServer: `updateClamshellState()` logs "Sending clamshell state closed: %u to WindowServer" and calls `requestClamshellState(kClamshellClosed)` (`pmconfigd/PMDisplay.m:231-258`). On lid open it creates the user-activity assertion `com.apple.powermanagement.lidopen` (same function, line 248).
- WindowServer then powers the panel down. `powerd` records the result as the log line "Display is turned off" (`PrivateLib.m:1468`). WindowServer is closed source, so the last step is seen only through its effect. [I for the WindowServer step]
- The kernel also refuses a display-on request while the lid is closed on battery: `checkSystemCanSustainFullWake()` returns false for "clamshell closed, no AC, no clamshell-disable bit" (`IOPMrootDomain.cpp:7793-7813`), and `handleSetDisplayPowerOn(true)` returns early in that case (line 8269).

Evidence from this Mac's `pmset -g log` [P-log]. How I read the lid: a HID tickle from service `AppleM68Buttons` at the same second as a new `lidopen` assertion marks a lid event (the code above creates `lidopen` on lid open).

1. Lid closed while the display was on, Mac awake, `SleepDisabled` set (no sleep followed):

```
2026-10-05 18:42:31 Notification  Display is turned off
2026-10-05 18:42:31 Assertions    PID 591(WindowServer) Summary UserIsActive "...service:AppleM68Buttons ... eventType:3" 00:00:05
2026-10-05 18:42:31 Assertions    PID 532(powerd) Summary UserIsActive "com.apple.powermanagement.lidopen" 00:06:45   [System: PrevIdle PrevSleep DeclUser kCPU kDisp]
2026-10-05 18:43:57 Notification  Display is turned on        (keyboard / trackpad activity)
```

   The display went off about 5 seconds after the lid sensor event. At that moment `UserIsActive` assertions were still held (`DeclUser kDisp`). An idle timer did not do this. The same pattern is at 19:45:29 to 19:47:56, with `InternalPreventDisplaySleep` also held.

2. Charger attached while the lid was closed and the Mac was awake:

```
2026-10-06 21:35:45 Assertions    PID 3653(PowerChime) Created DisplayWake "com.apple.chimeOnAttach"
2026-10-06 21:35:45 Notification  Display is turned on
2026-10-06 21:35:46 Notification  Display is turned off          <- 1 second later
2026-10-06 21:36:45 Assertions    PID 532(powerd) Created UserIsActive "com.apple.powermanagement.lidopen"   <- lid opened
2026-10-06 21:36:46 Notification  Display is turned on
```

   The system asked for the display, and took it away again in one second, because the lid was closed.

3. The Mac was awake from 2026-10-05 22:38:04 to 2026-10-06 09:12:19 with the display off the whole time (no "Sleep", "Wake" or "DarkWake" entry in that window; Agent Caffeine's assertions were summarized each 15 minutes). The lid was opened at 09:12:19 (`lidopen` + `AppleM68Buttons`).

Other reports:

- codex-clamshell README: "Close the MacBook lid while Codex is running a task: the screen turns off, but Codex keeps working." It uses `pmset disablesleep`. [C]
- clamshell.dev: "the built-in display stays black while the lid is closed". [C, vendor page]
- **Contrary claim:** LidSleepToggle README: "with the lid shut the internal panel is set to brightness 0 (it doesn't switch off by itself in clamshell-awake mode)". [C] This does not agree with the log above. Possible reasons: an older macOS, an Intel model, or a wrong reading by that author. The test in 1.7 settles it for this Mac in two minutes.
- Apple documents only closed-display mode with an external display. Apple gives no statement about the panel under a closed lid without a display. [U]

What I could not prove without closing the lid: that the backlight current is zero (not only "display state off"). The probe reads `AppleARMBacklight` -> `IODisplayParameters` -> `BrightnessMicroAmps` (3199 with the lid open at 75 percent brightness) and `CGDisplayIsAsleep`. The owner's test reads them with the lid closed.

Keyboard backlight and Touch Bar:

- Keyboard backlight: no primary source found. LidSleepToggle says it is "under 1 W anyway" and that the private `KeyboardBrightnessClient` can leave the backlight in a stuck suppressed state; they stopped touching it. [C] Do not touch it.
- Touch Bar (2016 to 2020 Intel models, 13-inch M1/M2 Pro): not examined. [U]

## 1.2 Lid closed with an external display

- On AC this is Apple's closed-display mode. The kernel does not sleep (`desktopMode && acAdaptorConnected`). The built-in panel is off. The external display is the main display. [P, note 02]
- The external display obeys the user's display sleep timer, because Agent Caffeine does not hold a display assertion. On this Mac the AC timer is `displaysleep 0` (never). That is the owner's own setting. [P, `pmset -g custom`]
- An external display uses wall power, not the battery (a bus-powered USB-C display on battery is the one exception).
- Should the app turn displays off when the user is away? No. The correct trigger would be "user idle for N minutes", and macOS already has that timer. A second timer in our app would fight the user's setting. If the owner wants it later, the API is in 1.4 (`IORequestIdle`), behind an opt-in.

## 1.3 Lid open, agent works, user away

- Agent Caffeine holds `PreventUserIdleSystemSleep` and `PreventSystemSleep`. It does not hold `PreventUserIdleDisplaySleep`. [P, `pmset -g assertions` on this Mac: both from pid `caffeinagent`, named "agent caffeine: 2 agents are working"]
- SDK header for `PreventUserIdleSystemSleep`: the display may dim and sleep. [P, note 05]
- So the display follows the user's display sleep timer. Log proof with our assertions held [P-log]:

```
2026-10-06 10:59:23 Assertions   PID 591(WindowServer) TimedOut UserIsActive "...AppleMultitouchDevice..."
2026-10-06 10:59:23 Assertions   Summary- [System: PrevIdle] Using Batt(Charge: 40)
2026-10-06 10:59:33 Notification Display is turned off
```

  On battery this Mac's timer is 2 minutes (`displaysleep 2`). Nothing to build.
- Note: another app can hold the display on. At the time of this research `pmset -g` showed "display sleep prevented by ego lite". That is not Agent Caffeine.

## 1.4 APIs that force the display off or to zero brightness

| API | What it does | Privilege | Apple silicon, macOS 15/26 | Evidence |
|---|---|---|---|---|
| `pmset displaysleepnow` = `IORegistryEntrySetCFProperty(IODisplayWrangler, "IORequestIdle", kCFBooleanTrue)` on `IOService:/IOResources/IODisplayWrangler` | Real display sleep. Same state as the idle timer. Wakes on any input. | None. `pmset.m` has no root check on this command (lines 717, 982-999; other commands print "must be run as root"). | `IODisplayWrangler` is present on this Mac (`ioreg -c IODisplayWrangler`). Not executed here (forbidden). | [P] code + registry; [I] that it works on this Mac |
| `IODisplaySetFloatParameter(kIODisplayBrightnessKey)` | Old public brightness call. | None | Returns success and changes nothing on Apple silicon. | [C] klart project, DEV article |
| `DisplayServicesSetBrightness(displayID, 0.0)` (private `DisplayServices.framework`, by `dlopen`/`dlsym`) | Backlight level 0. The panel stays powered. On an XDR mini-LED panel level 0 is very dark but not "off". | None | The read call `DisplayServicesGetBrightness` works here (returned 0.750). The set call is the one that LidSleepToggle and brightness tools use. | [P] read call on this Mac; [C] set call |
| `CoreDisplay_Display_SetUserBrightness` (private) | Older private path | None | Not verified on Apple silicon. | [U] |
| `CGDisplayCapture`, mirroring tricks, `CGSConfigureDisplayEnabled` | Hacks. They change the display layout and move windows. | None / private | Do not use. | [I] |
| `NSScreen` | No power control. | - | - | [P] |
| `IOPMSleepSystem` | Sleeps the whole Mac. Not a display call. | Console user | - | [P] `pmset.m:699` |

Display sleep while `SleepDisabled` is set: no problem found. The Mac ran 10.5 hours in that state on 2026-10-05/06 and the agents continued. The screen locks as the user's "require password" setting says. Terminal agents do not need the display. An agent that drives the screen (computer use) does need it. [P-log + I]

## 1.5 What uses the battery with the lid closed

Numbers from this Mac's log [P-log]. The battery gauge is coarse: it can show 100 while the raw charge is 96 to 97 percent (raw 5964 to 6039 mAh of 6220 mAh showed as 100 today). So each figure has an error of some points.

| State (14-inch M5 Pro, about 72 Wh) | Evidence | Drain |
|---|---|---|
| Asleep, lid closed, with macOS dark wakes | 2026-10-05 09:18 to 12:00: 100 -> 100; 2026-10-03 22:25 to 2026-10-04 01:56: 41 -> 40 | about 0.3 to 0.4 percent per hour, about 0.2 to 0.3 W |
| **Awake, lid closed, display off, one Claude Code session held as "working" but mostly idle** | 2026-10-05 22:38 to 2026-10-06 09:12 (10 h 34 min): 100 -> 93 displayed | **0.66 percent per hour displayed; 0.7 to 1.0 with the gauge error; about 0.5 to 0.75 W** |
| Awake, display off, agents active | 2026-10-01 02:14 to 03:44: 27 -> 24 | about 2 percent per hour |
| Awake, display off, agents working hard | 2026-10-03 17:52 to 20:40: 98 -> 79 | about 7 percent per hour |
| Awake, display on, heavy work | 2026-10-06 09:12 to 10:59: 93 -> 40 | about 30 percent per hour |

Published numbers [C]:

- Notebookcheck, MacBook Pro 14 M4: standby 0.28 W; idle minimum 2.1 W (display on at minimum brightness, measured at the wall); idle with a bright display 12.5 W.
- Notebookcheck, M4 Pro: idle 4.3 to 7.7 W at 150 cd/m2; 2.6 to 5.8 W with the internal panel off (external monitor). So the panel at 150 cd/m2 is about 2 W.
- MacRumors user with `powermetrics`, M4 Pro: display about 1 to 2 W.

Conclusion: a lit panel would cost 1 to 2 W, which is more than the whole idle Mac. So it would matter, if it were lit. It is not lit. Under a closed lid the cost is CPU work by the agents (2 to 30 percent per hour) and then the idle floor (under 1 percent per hour). There is no measurable benefit left for a display feature.

## 1.6 Other battery savers while holding with the lid closed

| Saver | How | Benefit | Risk |
|---|---|---|---|
| **Low Power Mode** | Root helper: `IOPMSetPMPreference` / `pmset -b lowpowermode 1` (on this model the key shows as `powermode`: 0 normal, 1 low, 2 high). Read with `ProcessInfo.isLowPowerModeEnabled`. | Eclectic Light, M4 Pro: about 25 percent of the power at about 50 percent of the speed for CPU-bound work. Large when agents build and test. Small when they wait on the model. [C] | It is a user setting in System Settings. It is stored on disk and survives a crash, like `SleepDisabled`. The helper must remember the old value, restore it, and restore it at next launch after a crash. Agents get slower: tell the user. Opt-in only. |
| Lower our own sampling rate on battery with the lid closed | Timer interval 2 s -> 5 to 10 s; keep the event sources | Small. The engine already costs under 0.02 percent of a core (note 05). | None. |
| Stop the hold earlier | Shorter grace period after the last agent signal when on battery with the lid closed | Each minute awake is a minute not asleep. | An agent that waits on the model can lose its hold. Keep the grace above the longest quiet gap you measured. |
| Battery floor, thermal stop, time cap | Already recommended in note 02 | Safety, not savings | - |
| Keyboard backlight off | Private `KeyboardBrightnessClient` | Under 1 W, and probably already off | Can leave the backlight stuck off (LidSleepToggle). **Do not build.** |
| `powernap 0`, `tcpkeepalive 0` | `pmset -b ...` | They act only while the Mac sleeps. No effect while we hold it awake. | `tcpkeepalive 0` breaks Find My (pmset prints that warning, `pmset.m:5801`). **Do not touch.** |
| Display to brightness 0 with the lid closed | `DisplayServicesSetBrightness` | None if the panel is already off | Brightness can stay at 0 after a crash. **Do not build**, unless the test in 1.7 shows a lit panel. |

## 1.7 Verdict and test plan for feature 1

**Verdict: do not build the display feature. Build the smaller thing: an opt-in "Low Power Mode while the lid is closed on battery", and a diagnostics line that shows the display state.**

Test plan (the owner, by hand, about 10 minutes plus one optional overnight run):

1. Unplug the charger. Start an agent task so that Agent Caffeine holds. Check `pmset -g | grep SleepDisabled` shows 1.
2. In Terminal run: `"${TMPDIR%/}/agent-caffeine-research/probe07/lidprobe" 2 > ~/lidprobe.tsv`
3. Wait 30 seconds with the lid open. Do not touch the Mac.
4. Close the lid. Look at the hinge gap in a dark room: there must be no glow. Wait 2 minutes.
5. Open the lid. Stop the probe with Control-C. Open `~/lidprobe.tsv`.
6. Read the rows where `lidClosed` is 1. Pass: `mainDisplayAsleep` is 1 (or `builtinOnline` is false), and `backlightMicroAmps` is 0 or much lower than in the lid-open rows. The `watts` column (negative = discharge) shows the real battery power with the lid open and with the lid closed.
7. Run `pmset -g log | grep -E "Display is turned|lidopen" | tail`. Pass: a "Display is turned off" line a few seconds after you closed the lid.
8. Optional, the number that matters: note `ioreg -r -c AppleSmartBattery | grep AppleRawCurrentCapacity`, leave the Mac for 2 hours with the lid closed and the hold active and no agent working, then read the value again. (Difference in mAh) x 11.5 V / 1000 / hours = watts. Repeat one time with Low Power Mode on (System Settings > Battery) to see what that switch is worth.
9. If step 6 fails (the panel is lit under the lid), tell me. Then the feature is real, and the API is `IORequestIdle` (true display sleep), with `DisplayServicesSetBrightness(0)` as the fallback.

---

# FEATURE 2 - wake the Mac by a message to the agent

## 2.1 What can wake a sleeping Mac from the network

| Wake source | What it is | Lid closed, battery | Lid closed, AC | Usable by a third-party app | Evidence |
|---|---|---|---|---|---|
| Wake on LAN magic packet (`womp`, "Wake for network access") | The network chip wakes the Mac on a magic packet. This Mac holds kernel assertion `MAGICWAKE en0` while on AC. | Off by default (`womp 0` on battery here) | Dark wake only | Only from the same LAN or a device on it. Result is a short dark wake, then sleep again. | [P] `pmset -g custom`, `pmset -g assertions`; [C] Apple forum 771999: "WOL only wakes the Mac for 30 seconds to 1 minute"; forum 656687: magic packet "does nothing" on a sleeping MacBook |
| Bonjour Sleep Proxy / Wake on Demand | An Apple TV, HomePod or AirPort answers for the Mac's Bonjour services and wakes it when a client asks for one (file sharing, screen sharing, SSH). | No. Old Apple text: portables do this "only ... when they are connected to a power adaptor and either the built-in display is open or an external display is connected". | No (lid closed without display) | Only for Bonjour services, only on the home LAN, only with a proxy device. | [P] Apple Support mh27905 (short); [C] copies of Apple's Wake on Demand article |
| `tcpkeepalive` | The Wi-Fi chip keeps Apple's push connection alive during sleep and wakes the Mac on data. Needed for Find My. The keepalive expires after 12 hours of sleep (`kTCPKeepAliveExpireSecs`). There is a wake quota (20 wakes per 3 hours by default, `Platform.c:40-41`). | **Yes, dark wake.** 212 dark wakes on battery in 7 days here; 194 with reason `wifibt`, each about 5 seconds. | Yes | **No.** The offload is for Apple's own connection (apsd). No public API registers a third-party socket. | [P] `pmset.m:5801`, `Platform.h:30`; [P-log] |
| Apple Push (APNs) to a third-party app | A push for our app arrives on apsd's connection. | apsd can wake the Mac only for topics that Apple marks as wake-capable (Find My, iCloud, Messages, FaceTime, MDM). powerd has a separate entitled assertion type for this (`InteractivePushServiceTask`, entitlement `kIOPMInteractivePushEntitlement`, `PMAssertions.c:6828`). | Same | **Not for wake.** A Developer ID app can receive pushes (provisioning profile + `com.apple.developer.aps-environment`), but only when the Mac is awake. | [P] powerd code for the entitled type; Apple DTS, forum 74662, on Developer ID push; [U] that third-party topics are never delivered in sleep (no Apple statement found) |
| Power Nap / maintenance dark wakes | macOS wakes itself for mail, iCloud, Time Machine, DHCP, mDNS. | Yes. Here: `SleepService` wakes about each 15 minutes (2 s), `Maintenance` wakes (5 to 45 s), plus the `wifibt` wakes. Median gap between wakes on battery: 35 s; 90th percentile 8 minutes; maximum 18 minutes. | Yes | Our process runs during them (see 2.2), but we cannot schedule them. | [P-log] |
| Scheduled wake (`pmset schedule wake`, `pmset relative wake`, `IOPMSchedulePowerEvent(kIOPMAutoWake)`) | The RTC wakes the Mac at a set time. | **Fires, as a dark wake.** Seen here for a `com.apple.alarm` request: `DarkWake ... rtc/Maintenance ... 5 secs` at 2026-10-04 00:53:01, lid closed, battery 40 percent. | Fires. | **Yes, with root.** powerd checks the caller's uid or the entitlement `kIOPMWakeRequestEntitlement` (`AutoWakeScheduler.c:1212-1215, 1289`). Our helper is root. | [P] code; [P-log] |
| Bluetooth HID, lid open, power button, charger attach (`acwake`), USB | User actions | The user is not there | - | No | [P-log] wake reasons `lid`, `USB-C_plug`, `HID Activity` |
| Tailscale / VPN packet | A tailnet packet is ordinary traffic to a sleeping interface. | No | No | No. A sleeping Mac drops off the tailnet. Tailscale has many sleep/wake issues. | [C] tailscale issues 1134, 20859, 21650 |
| SSH / Screen Sharing | Wake only through the Sleep Proxy path. An active SSH tty then blocks idle sleep (`ttyskeepawake`). | No | No | Home LAN only | [P] man pmset; [C] forum 771999 |
| MDM | Uses APNs wake topics. Needs an MDM enrollment. | - | - | Not for us | [C] |
| Continuity / Handoff / proximity (`proximitywake`) | Wake when a device with the same iCloud account is near. | Not with the lid closed [U] | [U] | No API | [P] man pmset |

## 2.2 Dark wake with the lid closed: what runs, for how long

- A closed lid on battery cannot go to full wake: `checkSystemCanSustainFullWake()` is false (`IOPMrootDomain.cpp:7802-7810`). Wakes become dark wakes. On AC the check passes, and then the lid is evaluated again and the Mac sleeps again ("Clamshell Sleep"). [P; I for the AC sequence]
- Dark wake = CPU, disk and network on, display and audio off. The log shows capability `[CDNP]` for dark wake and `[CDNVA]` for full wake. [P-log]
- User processes run in a dark wake. Apple DTS (Kevin Elliott, forum 770517): "we don't have any API for detecting DarkWake"; "Dark Wake isn't exposed through API as such, but it definitely 'leaks' into the larger system (with the most obvious example being the fact your app is awake)"; `kIOMessageSystemHasPoweredOn` is not delivered "because Dark Wake isn't considered 'On'". [P, Apple engineer]
- So `NSWorkspace.didWakeNotification` and `IORegisterForSystemPower` do not fire. The app must notice a dark wake itself: a wall-clock timer that fires late, or a general-interest notification on `IOPMrootDomain`. [P + I]
- Length: 5 seconds for a network wake, 2 seconds for `SleepService`, up to 45 seconds for maintenance (histogram of 231 dark wakes here: 118 x 5 s, 52 x 45 s, 14 x 2 s). [P-log]
- The app uses this length (`WakeGate.steadyAwake`, 120 seconds): after macOS said the Mac goes to sleep, a hold starts again at a full wake, or when the Mac was awake for more than 120 seconds with no sleep in between (a wake with the display off that stays, as an SSH login). **Assumed, not measured:** no maintenance dark wake lasts longer than 120 seconds. The longest one in the log above is 45 seconds. A longer one would let a stale "working" state take the sleep flag with the lid closed. [I]
- Can we hold a dark wake on battery?
  - `PreventSystemSleep`: no. Flag `kAssertionTypeNotValidOnBatt` (`PMAssertions.c`, type table). On AC it holds the dark wake (note 02). [P]
  - `BackgroundTask`, `MaintenanceActivity`, `InternalPreventSleep`: also not valid on battery. [P]
  - `PreventUserIdleSystemSleep`: header says "no effect if the system is in Dark Wake". [P]
  - **`SleepDisabled`: yes, by the code.** It is the first check in `checkSystemSleepAllowed()` and has no battery or lid condition (`IOPMrootDomain.cpp:7679`). If the root helper sets it during a dark wake, the next sleep request is refused and the Mac stays up (in dark wake: CPU and network on, display off). [P for the code; **[I] for the result. Not tested.**]
  - Clearing `SleepDisabled` does not start a sleep (`kPowerEventUserDisabledSleep` only stores the flag, line 8386). After the hold the helper must ask for sleep with `IOPMSleepSystem`. [P]
- Risk: `IOPMSetSystemPowerSetting` is asynchronous (preference file, notification, powerd, kernel: note 02). In a 5 second dark wake it can lose the race. A wake that we schedule ourselves is longer (see 2.4 D1), but that is also not proven.

## 2.3 How the remote features deliver a message

- **Claude Code Remote Control** [P, code.claude.com/docs/en/remote-control, read today]: "Your local Claude Code session makes outbound HTTPS requests only and never opens inbound ports on your machine. When you start Remote Control, it registers with the Anthropic API and polls for work." "if your laptop sleeps or your network drops, Claude Code reconnects automatically when your machine comes back online." Server mode: with no network "Claude Code gives up after roughly 10 minutes and the `claude remote-control` process exits." An interactive session "retries for as long as the outage lasts". "Presence heartbeats failing ... for about 30 minutes" disconnects an interactive session. Push notifications go from Claude to the phone only. No keep-awake setting. No wake feature.
- **Codex remote** [P, learn.chatgpt.com/docs/remote-connections, read today]: "If that computer sleeps, loses network access, or closes the app, remote access stops until it's available again." "On a Mac laptop, remote access can stay available with the lid open and power connected. With the lid closed, connect an external display as well." "Choosing Sleep still stops remote access." "Keep this Mac awake - Prevent sleep when computer is plugged in and remote access is enabled". Transport: "A secure relay layer". No wake feature.
- Neither vendor has a vendor-side wake. The message waits in the vendor's cloud until the Mac's process connects again. That is the useful fact: **the message is not lost. It is delivered when the Mac is next awake with a network.** [P for the quotes; I for "waits", from the "stored transcript ... lets the session reconnect" text of Claude Code; for Codex [U]]
- Consequences for a check-in design:
  - Claude Code interactive session (`/remote-control`): survives sleep, retries. Good candidate.
  - `claude remote-control` server mode: exits after about 10 minutes without network. Does a sleep count as "no network"? Process time does not run during sleep, so probably not, but [U]. Test it.
  - 30 minutes without a presence heartbeat disconnects an interactive session. So a check-in interval must stay well under 30 minutes. [I]
  - Codex desktop: reconnect time after wake is unknown. [U]

## 2.4 Designs

### D1. Check-in wakes

How it would work:

1. The Mac is asleep, lid closed. Remote access is enabled. The user enabled "check-in".
2. Before each sleep, the root helper schedules the next wake: `IOPMSchedulePowerEvent(date, CFSTR("<our bundle id>.checkin"), CFSTR(kIOPMAutoWake))`. One event at a time. Cancel the old one with `IOPMCancelScheduledPowerEvent` (same date, id and type). Check with `pmset -g sched`.
3. powerd treats a non-`com.apple.alarm` request as a full-wake request (`PMConnection.m:3432-3439`: `kChooseFullWake`, then `kIOPMAutoWakeScheduleImmediate` to the RTC). With the lid closed on battery the kernel cannot go to full wake, so the result is a dark wake. [P for the code; I for the result]
4. The helper notices the wake (late timer or root-domain interest), sets `SleepDisabled`, reads it back, and starts a 20 to 30 second window.
5. In the window the agents' remote processes reconnect and pull pending messages. If the engine sees an agent start work, the normal hold takes over.
6. If nothing happened: the helper schedules the next wake, clears `SleepDisabled` (only if we set it), and calls `IOPMSleepSystem`.

Questions and answers:

| Question | Answer | Evidence |
|---|---|---|
| Does a scheduled wake fire with the lid closed on battery? | Yes, as a dark wake. Seen for a `com.apple.alarm` wake on this Mac. | [P-log] |
| Is it a full wake? Does the display light? | No. Lid closed + battery cannot sustain full wake. The panel stays off under the lid in any case (1.1). | [P] |
| Does macOS refuse or merge frequent wakes? | No minimum interval in powerd (`MIN_SCHEDULE_TIME 0.0`). Limit of 1000 stored events. powerd picks the earliest of all requests, so our wake can only add wakes, not delay others. No throttle found in the open code. The firmware side is closed. | [P]; [U] for firmware |
| How long does our wake last without a hold? | Not known. The seen cases are 5 s (maintenance type). A full-wake type alarm under a closed lid can be as short. | [U] |
| Wake reason in the log | `rtc/...`; powerd also logs the requesting process for RTC wakes (`PMConnection.m:2492`). | [P] |
| Lock screen | The session stays locked. Nothing changes for the user. Terminal agents run while locked. | [P-log]: agents ran while locked overnight |
| Does it survive our crash? | Scheduled events are stored in a system preference file and stay until they fire. A stale event costs one extra wake. Clean them at launch. | [P] `AutoWakeScheduler.c` (`updateToDisk`) |
| Low battery | Add a floor. Below it, stop scheduling. | note 02 |
| Does `pmset schedule` show it to the user? | Yes, in `pmset -g sched`, with our id string. | [P] |

Battery cost estimate [I]. Assumptions: 30 second window at 1 to 3 W average (wake transition, Wi-Fi, TLS reconnect; not measured), on top of the sleep baseline of about 7 to 9 percent per day:

| N | Wakes per day | Extra energy | Extra percent per day (72 Wh) | Latency |
|---|---|---|---|---|
| 5 min | 288 | 2.4 to 7.2 Wh | 3 to 10 | up to 5 min |
| 15 min | 96 | 0.8 to 2.4 Wh | 1 to 3 | up to 15 min |
| 30 min | 48 | 0.4 to 1.2 Wh | 0.6 to 1.7 | up to 30 min (too close to Claude Code's 30 minute heartbeat limit) |

Unproven parts (each one can kill the design):

1. Our process gets enough run time in the wake to set `SleepDisabled` before the Mac sleeps again.
2. `SleepDisabled` holds a dark wake on battery with the lid closed.
3. The remote process reconnects and receives the pending message inside the window, and the engine sees the agent start.

Reliability if all three pass: medium. It depends on the vendors' reconnect logic, which can change in any release.

A cheaper variant: do not schedule anything. This Mac already has a dark wake about each 35 seconds to 8 minutes on battery (the `wifibt` wakes). The helper could extend each Nth of them. Latency then depends on macOS. Use our own scheduled wake only as the upper bound. Same unproven parts.

### D2. Our own push channel

- A Developer ID app can use APNs (provisioning profile, entitlement `com.apple.developer.aps-environment`). [P, Apple DTS]
- A push does not wake a sleeping Mac for a third-party app. The wake path in powerd is entitled. [P for the entitlement; U for the full statement]
- It also needs a relay server, a sender app or web page on the phone, and a second action by the user (the message to the agent does not pass through us).
- **Verdict: do not build.** High cost, and the central step is not available.

### D3. Wake on LAN, sleep proxy, helper device

- Works only on the home network. On battery `womp` is off by default. With the lid closed and no display, Wake on Demand is not supported on portables. A magic packet gives a short dark wake, which has the same hold problem as D1.
- An always-on device (Raspberry Pi, Apple TV with a tool, a Tailscale node that sends the packet) can do it for a user who wants to build that. It is a user project, not an app feature.
- **Verdict: do not build. Document as a tip at most.**

### D4. Never sleep on AC while remote access is on; time-boxed on battery

- On AC with the lid closed: the app does this today (PreventSystemSleep dark wake, plus `SleepDisabled`). Cost is wall power. No battery issue.
- On battery: "stay reachable for X hours, then sleep". This is D5 with a timer. See D5.

### D5. Stay awake and idle (no sleep) - the low-power awake state

- Mechanism: exactly the app's lid-closed hold (`SleepDisabled` + assertions), kept while remote access is enabled and no agent works. Display is off by itself (1.1). No new API.
- Measured on this Mac [P-log, one run]: 10 h 34 min awake, lid closed, display off: 100 -> 93 displayed. With the gauge error: **0.7 to 1.0 percent per hour, about 0.5 to 0.75 W.** Asleep on the same Mac: about 0.3 to 0.4 percent per hour. So "awake and idle" costs about 0.4 to 0.6 percent per hour more than sleep.
- Why sleep is not much better here: this Mac wakes itself very often while "asleep" (217 sleep periods in about 10 hours of battery sleep, median 35 seconds). An Apple Community thread reports the same dark wake loop on M5 Pro models. [P-log; C]
- What changes the number: anything that runs in the background (Docker, dev servers, browser tabs, Spotlight, backups). Other users can see 2 to 3 percent per hour. Published idle minimum for a 14-inch M4 with the display on at minimum brightness is 2.1 W at the wall [C]; with the display off it must be lower.
- Per day: 16 to 25 percent of a 72 Wh battery, against 7 to 9 percent asleep. 8 hours "reachable" costs about 6 to 8 percent, about 3 to 5 points more than sleep.
- Latency: zero. The remote connection stays up. Reliability: high. It is the state the app already ships.
- Low Power Mode can lower the cost of the agent's work after the message arrives (1.6).
- Risks: heat is low at idle, but the note 02 rules stay (battery floor, thermal stop, time cap, never in a bag). `SleepDisabled` also blocks low-battery sleep: the floor is required.

## 2.5 Verdict for feature 2

1. **Tell the truth in the UI:** a message cannot wake a sleeping Mac. The message waits and is delivered when the Mac is awake again.
2. **Build D5/D4 first: "Stay reachable".** When a remote feature is enabled (Claude Code Remote Control session, Codex remote access), keep the lid-closed hold after the agents stop, for a time the user chooses: 1, 2, 4, 8 hours, or "until the battery is at X percent". On AC: no limit. Show the cost: "about 1 percent per hour on this Mac" (replace with the app's own measurement: raw mAh over time, read from `AppleSmartBattery`).
   - APIs: none new. Helper: `IOPMSetSystemPowerSetting(kIOPMSleepDisabledKey)` with read-back (note 02). App: existing assertions. Add: battery floor, time cap, thermal stop, and "when the window ends, clear the flag and call `IOPMSleepSystem`".
3. **Then test D1 by hand (2.6).** If the three unproven parts pass, add "Check in every 15 minutes after the reachable window ends" as an experimental option. Use N = 10 to 15 minutes. Do not offer 30.
   - APIs: `IOPMSchedulePowerEvent` / `IOPMCancelScheduledPowerEvent` with `kIOPMAutoWake` (root helper), `IOPMSetSystemPowerSetting`, `IOPMSleepSystem`, `IOServiceAddInterestNotification` on `IOPMrootDomain` or a wall-clock timer to see the wake.
4. Do not build D2 or D3.

## 2.6 Test plans for feature 2 (the owner, by hand)

Test A: the real cost of "stay reachable" (D5). Safe. Uses only the app.

1. Charge to 100 percent. Unplug. Quit heavy apps that you do not need.
2. Start one Claude Code session with `/remote-control`. Make Agent Caffeine hold (or run `sudo pmset -a disablesleep 1` yourself for the test).
3. Note the time and `ioreg -r -c AppleSmartBattery | grep AppleRawCurrentCapacity`.
4. Close the lid. Leave the Mac for 3 hours on a table.
5. From the phone, send a message to the session after 1 hour and after 2 hours. Note how fast the agent answers. Pass: an answer in seconds.
6. Open the lid. Read `AppleRawCurrentCapacity` again. (Difference in mAh) / 6220 x 100 / hours = percent per hour. Compare with my figure of 0.7 to 1.0 (the agent's two answers add a little).
7. Restore: `sudo pmset -a disablesleep 0` if you set it by hand.

Test B: can a scheduled wake carry a message (D1)? This needs `sudo` and one schedule entry. I did not run it.

1. Unplug. Start a Claude Code session with `/remote-control`. Make sure Agent Caffeine is **not** holding (quit it for this test), so that the Mac really sleeps.
2. Schedule one wake 10 minutes ahead: `sudo pmset schedule wake "MM/DD/YY HH:MM:SS"`. Check with `pmset -g sched`.
3. Close the lid. From the phone, send a message to the session 3 minutes later. It must stay unanswered.
4. Wait until 5 minutes after the wake time. Open the lid.
5. Run `pmset -g log | grep -E "DarkWake|Wake |Sleep " | tail -40`. Find the entry at the wake time. Note its type (DarkWake or Wake), the reason (`rtc/...`) and the seconds.
6. Look at the session. Did the agent get the message during the wake, or only now? If the wake was 5 seconds and the message came only now, part 1 or part 3 failed without a hold: go to step 7.
7. Repeat steps 2 to 5 with a hold. Before you close the lid, start this in a root shell (`sudo -s`), with WAKE set to the wake time as epoch seconds (`date -j -f "%m/%d/%y %H:%M:%S" "MM/DD/YY HH:MM:SS" +%s`): `while [ $(date +%s) -lt $WAKE ]; do sleep 1; done; pmset -a disablesleep 1; sleep 40; pmset -a disablesleep 0; pmset sleepnow`. The loop stops while the Mac sleeps and continues at the wake. Send the phone message 3 minutes after you close the lid.
8. Pass for D1: the log shows the Mac up for about 40 seconds at the wake time, the agent started on the message in that window, and Agent Caffeine (start it again for this run) took the hold.
9. Also run the same test with `claude remote-control` (server mode) to see if it exits during sleep, and with Codex remote access.
10. Clean up: `pmset -g sched` must not show your wake entry (a fired entry is removed by itself; if it is still there, `sudo pmset schedule cancel wake "MM/DD/YY HH:MM:SS"` with the same date). Do not use `cancelall`: the list also holds Apple's own `com.apple.alarm` entries. `pmset -g | grep SleepDisabled` must show 0.

---

## 3. Sources

Primary:

- xnu `iokit/Kernel/IOPMrootDomain.cpp` (checkSystemSleepAllowed, checkSystemCanSustainFullWake, handlePowerNotification, handleSetDisplayPowerOn, wake type handling): https://github.com/apple-oss-distributions/xnu
- PowerManagement (tag PowerManagement-1846.0.25.0.1): `pmconfigd/PMDisplay.m`, `PMConnection.m`, `PMAssertions.c`, `AutoWakeScheduler.c`, `Platform.c`, `Platform.h`, `PrivateLib.m`, `pmset/pmset.m`: https://github.com/apple-oss-distributions/PowerManagement
- IOKitUser `pwr_mgt.subproj/IOPMAutoWake.c`: https://github.com/apple-oss-distributions/IOKitUser
- SDK `IOKit/pwr_mgt/IOPMLib.h`, `IOPMKeys.h` (IOPMSchedulePowerEvent, kIOPMAutoWake)
- `man pmset`; `pmset -g`, `-g custom`, `-g sched`, `-g assertions`, `-g log`; `ioreg` (IOPMrootDomain, IODisplayWrangler, AppleARMBacklight, AppleSmartBattery) on this Mac
- Claude Code Remote Control: https://code.claude.com/docs/en/remote-control
- Codex remote connections: https://learn.chatgpt.com/docs/remote-connections (redirect from developers.openai.com/codex/remote-connections)
- Apple DTS on dark wake: https://developer.apple.com/forums/thread/770517
- Apple DTS on Developer ID push: https://developer.apple.com/forums/thread/74662
- Apple Support, share resources in sleep: https://support.apple.com/guide/mac-help/share-your-mac-resources-when-its-in-sleep-mh27905/mac
- Apple Support, sleep and wake settings: https://support.apple.com/guide/mac-help/set-sleep-and-wake-settings-mchle41a6ccd/mac

Community:

- codex-clamshell: https://github.com/llmpolska/codex-clamshell
- clamshell.dev guide: https://clamshell.dev/guides/macbook-lid-closed-on-battery
- LidSleepToggle: https://github.com/Sufxx/LidSleepToggle
- klart (brightness on Apple silicon): https://github.com/WertCore/klart and https://dev.to/crimsondhaks/macos-has-no-public-api-for-screen-brightness-jk5
- Notebookcheck MacBook Pro 14 M4: https://www.notebookcheck.net/Apple-MacBook-Pro-14-M4-review-The-M4-base-model-with-important-improvements.923443.0.html
- Notebookcheck M4 Pro: https://www.notebookcheck.net/Apple-M4-Pro-14-cores-Processor-Benchmarks-and-Specs.915303.0.html
- Eclectic Light, power modes: https://eclecticlight.co/2025/01/08/power-modes-and-apple-silicon-cpus/ and https://eclecticlight.co/2025/01/22/m4-pro-full-on-when-cpu-and-gpu-draw-over-50-w-and-how-low-power-mode-changes-that/
- MacRumors, M4 Pro display power: https://forums.macrumors.com/threads/m4-pro-mbp-68w-total-power-consumption-but-only-40w-processor-power-whats-consuming-the-remaining-28w.2463816/
- Apple Community, M5 Pro dark wake drain: https://discussions.apple.com/thread/256265048
- Apple forum, WoL and dark wake: https://developer.apple.com/forums/thread/771999 and https://developer.apple.com/forums/thread/656687
- Bonjour Sleep Proxy: https://en.wikipedia.org/wiki/Bonjour_Sleep_Proxy
- Tailscale sleep issues: https://github.com/tailscale/tailscale/issues/1134 , https://github.com/tailscale/tailscale/issues/20859 , https://github.com/tailscale/tailscale/issues/21650

Read only through search summaries (treat as [U]): the claim that APNs never delivers third-party pushes to a sleeping Mac; the Wake on Demand portable rule (Apple's original article is no longer online); Notebookcheck and Eclectic Light figures (I did not open the pages).

Not done: no lid was closed, no display was put to sleep, no wake was scheduled, no setting was changed. Every hardware claim marked [I] or [U] needs the owner's test.
