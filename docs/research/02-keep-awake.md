# 02 - How to keep a Mac awake (lid closed, on battery)

Research date: 2026-10-05. Read-only. No power setting was changed.
Test Mac for local reads: Apple silicon (arm64), macOS 26.7.1 (25G241).

Evidence labels used in this file:

- **[P]** primary source: Apple open source code, Apple headers, Apple man pages, open source app code, or a read-only command on this Mac.
- **[C]** community report: README claims, issues, blog posts, forum posts.
- **[I]** my inference from primary source. Not tested on hardware.
- **[U]** unconfirmed. I found a claim but no evidence, or I could not open the source page.

Source files that I downloaded are in `src/` next to this file
(`IOPMrootDomain.cpp`, `RootDomainUserClient.cpp`, `PMAssertions.c`, `pmconfigd.m`, `PMSettings.m`, `pmset.m`, `caffeinate.c`, `IOPMEnergyPrefs.c`, Codex `sleep-inhibitor`, Amphetamine Enhancer, READMEs of competitor apps). Line numbers below refer to those files (branch `main` of `apple-oss-distributions/xnu`, `PowerManagement`, `IOKitUser` on 2026-10-05).

---

## 0. Short answer

1. There are only **three** mechanisms that keep a MacBook awake with the lid closed and no external display:
   - `SleepDisabled` (what `pmset disablesleep 1` sets). Needs root. Works on AC and battery.
   - The clamshell bit: `IOPMrootDomain` user-client selector `kPMSetClamshellSleepState`. Needs **no** root. Works on AC and battery, but `powerd` owns that bit and writes over it.
   - A `PreventSystemSleep` assertion. Works lid closed **on AC only**. The Mac goes to dark wake and continues to run.
2. `SleepDisabled` is the only one that the kernel obeys without conditions. It is the correct load-bearing mechanism for "lid closed on battery". Our current approach is the same as most competitors and the same as Amphetamine's own "Power Protect".
3. I found **no primary evidence** that `SleepDisabled` fails on Apple silicon. The kernel code checks it first, before all other sleep conditions. The reports of failure have other causes (section D).
4. `SleepDisabled` has three properties that the app must handle: it is **written to disk and survives a reboot**, it is **global** (one flag, many possible writers), and it also **blocks low-battery sleep and thermal-emergency sleep** in the open source kernel.
5. `pmset -b disablesleep 1`: the `-b` does nothing. `disablesleep` is a system-wide setting, not a per-power-source setting.

---

## A. How other apps do it

### A.1 Mechanism list (from source)

| # | Mechanism | What it does in the kernel / powerd | Privilege | Evidence |
|---|---|---|---|---|
| 1 | `PreventUserIdleSystemSleep` assertion (`caffeinate -i`) | Stops the idle sleep timer only. Lid close is a demand sleep, not an idle sleep. | none | [P] `caffeinate.c:53`, man page |
| 2 | `PreventUserIdleDisplaySleep` (`caffeinate -d`) | Keeps the display on. No effect when the lid closes. | none | [P] |
| 3 | `PreventSystemSleep` (`caffeinate -s`) | Blocks full system sleep, but **not dark wake**. Type is flagged "not valid on battery" unless the caller has a private entitlement. | none on AC | [P] `PMAssertions.c:3320, 5860, 6450`; `IOPMrootDomain.cpp:7698` |
| 4 | `UserIsActive` (`caffeinate -u`) | Declares user activity. Turns the display on. Default timeout 5 seconds. | none | [P] man page |
| 5 | `PreventDiskIdle` (`caffeinate -m`) | Disk idle only. | none | [P] `caffeinate.c:57` |
| 6 | Assertion property `AppliesOnLidClose` | The official "stay awake with lid closed" switch. powerd counts these and disables clamshell sleep. | **Apple-private entitlement** (`kIOPMAssertOnLidCloseEntitlement`) | [P] `PMAssertions.c:2571-2578, 1396-1430` |
| 7 | Assertion property `AppliesToLimitedPower` | Makes `PreventSystemSleep` valid on battery. | **Apple-private entitlement** (`kIOPMAssertOnBatteryEntitlement`) | [P] `PMAssertions.c:2561-2568` |
| 8 | `kPMSetClamshellSleepState` (RootDomainUserClient selector) | Sets/clears bit `kClamshellSleepDisablePowerd` in `clamshellSleepDisableMask`. When the mask is non-zero the kernel does not sleep on lid close. | **none**: `checkEntitlement = NULL`, no privilege check | [P] `RootDomainUserClient.cpp:388-396, 525-529`; `IOPMrootDomain.cpp:4462-4471, 4541-4567` |
| 9 | `SleepDisabled` (`pmset disablesleep 1`, `IOPMSetSystemPowerSetting(kIOPMSleepDisabledKey)`) | Sets `userDisabledAllSleep`. `checkSystemSleepAllowed` returns false first thing: "user-space sleep kill switch". Pegs the system at full wake. | **root** (`getuid()==0` check in IOKitUser; kernel side needs an entitlement that powerd has) | [P] `IOPMEnergyPrefs.c:1622-1662`; `PMSettings.m:1330-1347`; `IOPMrootDomain.cpp:2055-2059, 7673-7682, 8386-8389` |
| 10 | Desktop mode (external display, real or dummy) | Kernel formula uses `desktopMode && acAdaptorConnected`. A display alone does nothing on battery. | none | [P] `IOPMrootDomain.cpp:4470` |
| 11 | Kernel extension (InsomniaX, NoSleep) | Hooked the clamshell event in the kernel. | kext + reduced security on Apple silicon | [C] both projects are dead; NoSleep README says "DEPRECATED ... same behavior could be achieved by using `pmset` or `caffeinate`" |

The kernel decision for lid close, verbatim [P]:

```cpp
// IOPMrootDomain::shouldSleepOnClamshellClosed
return !clamshellDisabled && !(desktopMode && acAdaptorConnected) && !clamshellSleepDisableMask;
```

### A.2 `caffeinate` flags [P]

Source: `man caffeinate` on macOS 26.7.1 and `caffeinate.c`.

| Flag | Assertion | Note |
|---|---|---|
| (none) | `PreventUserIdleSystemSleep` | default |
| `-i` | `PreventUserIdleSystemSleep` | idle sleep only |
| `-d` | `PreventUserIdleDisplaySleep` | display |
| `-m` | `PreventDiskIdle` | disk |
| `-s` | `PreventSystemSleep` | man page: "valid only when system is running on AC power" |
| `-u` | `UserIsActive` | turns display on; 5 second default timeout |
| `-t N` | timeout in seconds | ignored when a utility is given |
| `-w pid` | sets `AssertionOnBehalfOfPID`, waits for the pid | ignored when a utility is given |

No `caffeinate` flag stops lid-close sleep on battery. `-s` holds the Mac in dark wake with the lid closed on AC (see B.3).

### A.3 App by app

| App | Mechanism | Lid closed, AC | Lid closed, battery | Apple silicon | Privilege | Evidence |
|---|---|---|---|---|---|---|
| **Amphetamine** (Mac App Store, sandboxed, closed source) | Assertions + closed-display mode. Community says closed-display mode is the `kPMSetClamshellSleepState` call. | yes | yes | yes, but "may not work as expected after connecting or disconnecting ... power" | none for base app | Mechanism: [C] (LidOn, Orexin, jetlink PR say "same call as Amphetamine"; not verified, app is closed source). Apple silicon problem: [P] developer README |
| **Amphetamine Power Protect** | A script in `~/Library/Application Scripts/com.if.Amphetamine/powerProtect.scpt` plus a **sudoers drop-in** `/private/etc/sudoers.d/amphetamine_powerProtect`. Fixes the power-change problem on Apple silicon. Developer: "Apple provides no other way." | yes | yes | made for Apple silicon only | sudoers drop-in, installed one time with Touch ID / admin password | [P] developer README. Script content not published; [I] it runs `pmset disablesleep`, because that is the only root-level lid mechanism |
| **Amphetamine Enhancer** | Launch agents + shell scripts. "Closed-Display Mode Fail-Safe" checks if Amphetamine is alive and has an assertion; if not, it restores lid sleep. Proves the lid state survives the app's death. | n/a | n/a | yes | user launch agent | [P] `amphetamine-enhancer-cdmManager.sh` |
| **Caffeine** (Lighthead), **KeepingYouAwake** | KeepingYouAwake is "a small wrapper around Apple's `caffeinate`". README: "Does it work on a MacBook with a closed lid? No." | no | no | yes | none | [P] KeepingYouAwake README |
| **Lungo** | Assertions. FAQ: lid closed "is not allowed for apps on the App Store". Works lid closed only with charger + external display. | only with display | no | yes | none | [C] search summary of developer FAQ |
| **Theine** | Assertions. Does not hold with lid closed and no monitor. | no | no | yes | none | [C] |
| **Jolt of Caffeine** | Assertions (App Store app). No lid-closed data found. | [U] | [U] | yes | none | [U] |
| **Sleep Control Centre** | Claims a "Prevent System Sleep when lid is closed" mode. Mechanism not published. | [U] | [U] | [U] | [U] | [C] vendor help page |
| **InsomniaX**, **NoSleep** | Kernel extension. Dead. InsomniaX had a security hole that let unsigned kexts load. | n/a | n/a | not usable | kext | [P] project READMEs |
| **Macs Fan Control**-style helpers | Not a sleep tool. Relevant only as a pattern: root helper daemon for SMC access. | n/a | n/a | n/a | root helper | [U] not examined |
| **Claude Code CLI** | Spawns `caffeinate -i -t <N>` while the TUI is busy and restarts it on an interval. Idle sleep only. No lid support. No setting to turn it off. | no | no | yes | none | [P] strings in the local binary 2.1.289 (`getSpawnArgs(){... return["caffeinate",["-i","-t",e]]}`, "Restarting sleep inhibitor to maintain prevention"). Values 300 s timeout / 240 s restart / 30 s linger and the kill-before-spawn gap: [C] issues anthropics/claude-code #21432 (2026-01-28) and #81832 (2026-07-28, v2.1.220) |
| **Claude Desktop** | Electron `powerSaveBlocker('prevent-app-suspension')`, shown as `NoIdleSleepAssertion "Electron"`, held from launch to quit. | no | no | yes | none | [C] issue #45769 (2026-04-09), closed "not planned" |
| **Codex CLI** | In-process `IOPMAssertionCreateWithName("PreventUserIdleSystemSleep")`, reason "Codex is running an active turn". Explicitly "instead of spawning `caffeinate`". Held only while a turn runs, behind an enable flag. | no | no | yes | none | [P] `openai/codex` `codex-rs/utils/sleep-inhibitor/src/{lib,macos}.rs` |
| **ChatGPT / Codex desktop app** "prevent sleep" setting | Not verified. | [U] | [U] | | | [U] |
| **VS Code, Cursor** (Electron) | Electron `powerSaveBlocker` when an extension or feature asks. Idle sleep only. | no | no | yes | none | [C] Electron docs; no lid mechanism exists in Electron |
| **JetBrains IDEs** | Not verified. | [U] | [U] | | | [U] |
| **Docker Desktop** | No evidence of a lid mechanism. | no [U] | no [U] | | | [U] |
| **Tailscale** | Does not keep the Mac awake. Many issues about the tunnel after sleep/wake (#15838, #17727, #20859). A sleeping Mac drops the tailnet session. | no | no | | | [C] |
| **Orca** (agent IDE) | `caffeinate -i -s` + Electron display blocker. Bug report: does not hold lid closed without a display. | dark wake only | no | | none | [C] stablyai/orca #20194 (2026-09-12) |
| **LidOn** (agents, MCP `keep_awake`) | `kPMSetClamshellSleepState` re-applied **every second**, **plus** `pmset -a disablesleep` through a sudoers rule while the lid is closed. Says: "When a charger or display is plugged in or out with the lid closed, macOS re-checks the lid and overrides the setting ... which would put the Mac to sleep." Watchdog process. Battery floor 10 %, battery 45 °C, thermal pressure. | yes | yes | yes + Intel | none for AC; sudoers for unplug safety | [P] README |
| **Orexin** (tompopham/Awake) | `kPMSetClamshellSleepState` only, re-applied on a 10 s timer + power-source notification + wake. "No root, no sudo." Off below 10 % battery or critical thermal. | yes | yes | Apple silicon only | none | [P] README |
| **LidKeeper** | Started with the clamshell selector. **Moved to `pmset -a disablesleep`**: "The previous private clamshell selector accepted calls on this Mac but did not reliably prevent closed-lid sleep ... `powerd` could change it back." Narrow sudoers rule + LaunchAgent watchdog. Off at 20 % battery, serious thermal. | yes | yes | Intel tested | sudoers | [P] README |
| **LidSleepToggle** | `pmset -a disablesleep 0|1` via sudoers. Tracks Claude Code by session-file mtime. Sets internal panel brightness to 0 because "it doesn't switch off by itself in clamshell-awake mode". Battery floor 20 %, critical 10 % (then forces sleep), 95 °C sensor limit, 8 h cap. | yes | yes | yes | sudoers | [P] README |
| **Sleepless** (Aboudjem / mmavko) | `pmset -a disablesleep` via sudoers. Battery floor 15 %, timer, watchdog agent. "Confirmed on macOS 26.3", M1/M2/M3. | yes | yes | yes | sudoers | [P] README (their test claim is [C]) |
| **Electronic Clam (eclam)** | `IOPMSetSystemPowerSetting("SleepDisabled")` from an **`SMAppService` root daemon** over `NSXPCConnection`. Developer ID signed. Refuses to register the helper from a quarantined or translocated copy. Optional invisible virtual display so the screen does not lock on lid close (keeps a VPN alive). Battery floor 30 % lid-closed, thermal. | yes | yes | Apple silicon only, macOS 13+ | SMAppService daemon (user approves in Login Items) | [P] README |
| **Awake (oviron, from Limitless)** | "A signed, authenticated root helper controls closed-lid sleep." Notes: "The macOS `disablesleep` flag is global ... Use one writer." | yes | yes | yes + Intel | root helper | [P] README |
| **clamshell.dev** | "unprivileged IOKit clamshell sleep control plus an idle-sleep assertion", re-applied on power change. Low battery disarm 20 %. Thermal protection always on. macOS 14+, Apple silicon. | yes | yes | yes | none | [C] vendor page |
| **batt / Battery Toolkit** | Battery Toolkit uses `IOPMSetSystemPowerSetting(kIOPMSleepDisabledKey, true)` from its root daemon. | yes | yes | yes | root daemon | [C] charlie0129/batt #149 |
| Virtual display / dummy HDMI (BetterDisplay etc.) | Triggers desktop mode. Kernel needs AC too. Reports of breakage in clamshell on macOS 15.4.1. | yes | **no** | yes | none | [P] kernel formula; [C] BetterDisplay #4312 |

Pattern across the field: apps that tried the no-root clamshell bit alone report that it is not reliable; the ones that claim reliability on battery use `SleepDisabled` through sudoers or a root helper.

---

## B. What decides clamshell sleep

### B.1 The moving parts [P]

- **`AppleClamshellState`** (IORegistry, `IOPMrootDomain`): lid is closed (true/false). Read only.
- **`AppleClamshellCausesSleep`**: output of `shouldSleepOnClamshellClosed()`. Read only. It is a report, not a switch. Note: it does **not** include `SleepDisabled`. On this Mac it showed `Yes` at the same time as `SleepDisabled = Yes` [P local `ioreg`]. Do not use it to check that the Mac will stay awake.
- **`clamshellDisabled`**: set by the graphics stack with `kIOPMDisableClamshell`.
- **`desktopMode`**: external display present. Only counts together with `acAdaptorConnected`.
- **`clamshellSleepDisableMask`**: two bits. `kClamshellSleepDisableInternal` (kernel, during display probing) and `kClamshellSleepDisablePowerd` (set through `kPMSetClamshellSleepState`).
- **`SleepDisabled`** → `userDisabledAllSleep`: checked first in `checkSystemSleepAllowed()`, used by `privateSleepSystem()` for every sleep reason.

### B.2 Who writes the clamshell bit [P]

`powerd` (`PMAssertions.c:1389-1470`, `setClamshellSleepState`) computes the bit from:

1. desktop mode,
2. assertions that carry the entitled `AppliesOnLidClose` property,
3. on Apple silicon only: a WindowServer `PreventSleep` assertion with `ProcessingHotPlug` (display hot-plug).

It calls the selector only when its own value changes between zero and non-zero. So a third-party "1" stays until powerd's own state goes 1 → 0. That happens on display plug/unplug, on hot-plug processing (Apple silicon), and around sleep/wake (`pmconfigd.m:409-437`). At that moment powerd writes 0 and the third-party value is gone. This matches the Amphetamine README ("after connecting or disconnecting ... power source"), LidOn, Orexin, jetlink and LidKeeper reports. [P] for the code, [I] for the link to the reports.

Also [P]: "do not modify clamshell sleep state in dark wake" (`PMAssertions.c:1442-1452`, Apple silicon only).

### B.3 Dark wake and AC [P]

- `PreventSystemSleep` "prevent[s] system sleep but does not prevent dark wake" (`IOPMrootDomain.cpp:7693-7695`).
- Local proof on this Mac (`pmset -g log`, macOS 26.7.1, Apple silicon): seven lines `Entering DarkWake state due to 'Clamshell Sleep' ... Using AC`, and separate lines `Entering Sleep state due to 'Clamshell Sleep' ... Using Batt`. So with our `PreventSystemSleep` assertion, lid closed on AC = dark wake; lid closed on battery = real sleep.
- In dark wake the CPU and network run and user processes continue. Graphics and audio are off. This is why `caffeinate -s` "works" lid closed on AC. [P] for the state, [I] that all agent work continues correctly in it (terminal agents do; anything that needs the window server to draw may not).
- When AC is removed with the lid closed, the kernel re-evaluates the clamshell immediately (`kIOPMSetACAdaptorConnected` → `eval_clamshell`, `IOPMrootDomain.cpp:8806-8822, 8892-8894`) and the assertion is no longer valid on battery. A user-space app cannot react in time. [I]

### B.4 `pmset -g` fields

| Field | Meaning | Relevance |
|---|---|---|
| `SleepDisabled` | the kill switch. `pmset -g` prints it under "System-wide power settings". The argument name is `disablesleep`. [P] `pmset.m:1196-1198` | load-bearing |
| `sleep` | idle sleep timer in minutes (0 = never). Idle only. Does nothing for the lid. [P] man page | not enough |
| `displaysleep`, `disksleep` | idle timers | no |
| `standby`, `hibernatemode`, `autopoweroff` | what happens **after** the Mac is asleep (write RAM image, power down). [P] man page | no effect while awake |
| `powernap` | lets a sleeping Mac do Apple background tasks in dark wake | third-party work does not run in Power Nap [I] |
| `tcpkeepalive` | keeps some TCP sessions alive during sleep for Apple services | does not keep an agent's API stream alive [I] |
| `womp` | "Wake for network access" (magic packet) | wake only |
| `ttyskeepawake` | idle sleep is blocked while a remote tty is active. Idle only. | does not stop lid sleep |
| `lidwake`, `acwake` | wake triggers | no |
| `powermode` / `lowpowermode` | Low Power Mode (0 normal, 1 low, 2 high) | no sleep-policy link found in `IOPMrootDomain.cpp` or in the clamshell code [P for absence in the files I read; U for the rest of the system] |

`powerd` is the user-space daemon that owns assertions, applies settings to the kernel, and has the entitlements. It is the only process that should set `SleepDisabled` in the kernel: `pmset` and `IOPMSetSystemPowerSetting` only write a preference and post a notification; powerd then sets the registry property. [P] `IOPMEnergyPrefs.c:1650-1660`, `PMSettings.m:1330-1347`.

### B.5 Network with lid closed

- While the system is at full wake (SleepDisabled set) nothing in the code I read turns Wi-Fi off. Competitor apps run SSH, MCP and phone-push over the network in this state. [C]
- The screen **locks** on lid close. eclam reports that this drops a FortiClient SSL VPN and uses a virtual display to stop the lock. Agents that need the login keychain or a VPN can be affected. [C]
- A sleeping Mac loses Tailscale / VPN sessions. [C]

### B.6 Low battery and heat

- With `SleepDisabled` set, `privateSleepSystem()` returns `kIOReturnNotPermitted` for **every** reason, and that includes `kIOPMSleepReasonLowPower` and `kIOPMSleepReasonThermalEmergency` (`IOPMrootDomain.cpp:2899-2913, 7673-7682`). So in the open source kernel the kill switch also blocks the software low-battery sleep and thermal-emergency sleep. The Mac then runs until firmware or battery protection cuts power. [P] for the code path, [I] for the end result on hardware.
- The community claim "at a low enough charge macOS forces sleep regardless of pmset, at hardware level" is [U]. The code suggests a hard power-off is more likely than a clean sleep.
- With only the clamshell bit set (no `SleepDisabled`), low-battery and thermal sleep still work normally. [P]
- Apple: use the laptop on a surface with good ventilation; do not cover it. Apple supports closed-lid use only in closed-display mode (power + display + input). [C, Apple Support 102336; page read through search summary only]
- What responsible apps do [P from READMEs]:

| App | Battery floor | Heat | Time | Crash safety |
|---|---|---|---|---|
| LidOn | 10 % | serious thermal pressure or battery 45 °C | max 12 h per request | separate watchdog process |
| LidKeeper | 20 % | serious / critical thermal pressure | 30 m / 1 h / 2 h | LaunchAgent, 60 s heartbeat |
| LidSleepToggle | 20 % release, 10 % force sleep | critical pressure or 95 °C sensor | 8 h hard cap | restores at next launch |
| Sleepless | 15 % (5-50) | logged, not enforced | 1 h / 2 h | watchdog agent |
| eclam | 30 % lid closed, 10 % else | macOS signal + own signal | timer, default 2 h | root helper auto-release |
| Orexin | 10 % | critical thermal | none | bit clears on reboot |
| clamshell.dev | 20 % (5-50) | serious / critical, always on | - | - |
| Amphetamine | trigger on battery % | no | session length | Enhancer fail-safe |

All of them say: never run it in a bag.

---

## C. Cleaner than a sudoers entry?

| Option | How | User experience | Notarization (Developer ID, outside the store) | Survives OS update | Risk |
|---|---|---|---|---|---|
| **sudoers drop-in** `/etc/sudoers.d/<app>` for exactly `/usr/bin/pmset -a disablesleep 0` and `1` | App runs `sudo -n pmset ...` | One admin prompt at install. No prompt later. | No effect on signing. | Yes in practice: `/etc/sudoers.d` is user data. [C/U, no Apple statement] | Any process of that user can run the two commands. A wrong file can break `sudo` (use `visudo -c`). Left behind when the app is deleted. `/usr/bin/pmset` is on the sealed system volume, so the path is safe. |
| **`SMAppService.daemon(plistName:)` root helper** (macOS 13+) | Helper binary + launchd plist inside the app bundle (`Contents/Library/LaunchDaemons`). App talks to it over XPC. Helper calls `IOPMSetSystemPowerSetting` or runs `/usr/bin/pmset`. | User approves in System Settings > General > Login Items (admin auth). No Terminal. Shows the app name in Login Items. | Yes. This is Apple's supported path. Needs a correct Developer ID signature; fails from a quarantined / translocated copy (eclam handles this). | Yes. Removed when the app is deleted. | More code. The helper must check the code signature of the XPC client or it becomes a root service for all. Known Ventura 13.6 bug with disabling. [C theevilbit] |
| **`SMJobBless`** | Old privileged helper install | Password prompt | Works, but deprecated since macOS 13 | Yes | Do not start new work on it. [C] |
| **AuthorizationServices one-time prompt** (`AuthorizationExecuteWithPrivileges`, or `osascript ... with administrator privileges`) | Run `pmset` as root at each toggle | **A password prompt at each toggle.** Not possible for an app that toggles by itself. | `AuthorizationExecuteWithPrivileges` is deprecated since 10.7 | n/a | Good only for the one-time install step of the other options. |
| **`IOPMSetSystemPowerSetting` directly from the app** | Private IOKit SPI | Fails without root (`kIOReturnNotPrivileged`). [P] | Private symbol; acceptable outside the store, not in the store | SPI can change | Only useful inside a root helper. |
| **`kPMSetClamshellSleepState` from the app** | Private selector number (12) on the root domain user client | **No prompt at all** | Private selector; acceptable outside the store. (Amphetamine reportedly ships it in the store. [C]) | The selector index can change in any macOS release. Apple can add an entitlement check at any time. | Not reliable alone (B.2). The bit stays set if the app dies, until reboot or until powerd rewrites it. |

Notes [P]:

- `IOPMSetSystemPowerSetting` and `pmset disablesleep` are the same thing. `pmset.m:802` calls `IOPMSetSystemPowerSetting`.
- The setting is stored in `/Library/Preferences/com.apple.PowerManagement.plist` under `SystemPowerSettings.SleepDisabled`, and powerd re-applies it at start (`PMSettings.m:1162, 1330`). I read this file on this Mac: it contained `SleepDisabled => false` two minutes after `pmset -g` had shown `1`, and its modification time matched the change. So the flag **persists across reboot**. The Sleepless README says "Reboot: macOS resets `disablesleep` to 0"; LidOn says "the setting survives restarts". The source agrees with LidOn.
- The call is asynchronous: it writes the preference and posts a notification; powerd sets the kernel flag later. A caller must read back the kernel value (IORegistry `IOPMrootDomain` → `SleepDisabled`, or `pmset -g`) before it trusts it.

Which one for us: sudoers is acceptable and is the industry norm for small apps (and for Amphetamine itself). The `SMAppService` daemon is the cleaner product: one approval in System Settings, no Terminal, removed with the app, and a root helper can also be the watchdog that clears the flag when the app dies or after a reboot.

---

## D. Does `pmset disablesleep 1` fail on Apple silicon?

What I found:

1. **No primary evidence of failure.** In the current XNU source, `userDisabledAllSleep` is the second check in `checkSystemSleepAllowed`, before battery, thermal, assertions and clamshell. `privateSleepSystem` (the function that the lid-close path calls) returns "not permitted" when it is set. [P]
2. Positive reports on Apple silicon: Sleepless "confirmed on macOS 26.3" on M1/M2/M3; LidOn, LidSleepToggle, eclam, Battery Toolkit, helmlet all ship it for Apple silicon. [C]
3. One article (pasqualepillitteri.it) says: from macOS Ventura on Apple silicon "a hardware control ... forces sleep when the lid magnet detects closure" and `disablesleep 1` "is no longer enough". I could not open the page (connection failed twice). It gives no source in the search summary, and it contradicts the kernel code and the reports above. [U], probably wrong.
4. A MacRumors thread about the M2 Air has user reports that the Mac "still goes to sleep" with third-party apps. I could not open it (HTTP 403). The summary points at apps, not at `disablesleep`. [U]
5. The well-documented Apple silicon failure is a different mechanism: the **clamshell bit** (Amphetamine closed-display mode) is lost when a charger or display is connected or disconnected. [P] README + [P] powerd code.
6. macOS 26.0: reports of Macs that did not wake after lid-close sleep; fixed in 26.1. Not a `disablesleep` problem. [C]

Probable causes of "it did not hold" in our app (ordered by likelihood) [I]:

- **Race.** The flag is applied asynchronously through powerd. If the lid closes, or AC is removed with the lid closed, before the flag is in the kernel, the Mac sleeps. We set the flag only on battery, so "unplug while closed" always loses the race.
- **Another writer.** The flag is global. Amphetamine Power Protect, LidOn, Sleepless, batt and others also write it. Any of them can write 0 while we want 1.
- **Silent `sudo` failure.** `sudo -n` fails when the sudoers file is missing, has wrong permissions, or the command string differs by one character (for example `-b` vs `-a`). Without a read-back the app does not know.
- **Sleep already in progress** when the flag is set.
- **Wrong check.** `AppleClamshellCausesSleep` stays `Yes` when `SleepDisabled` is 1 (seen on this Mac), and `pmset -g custom` does not show the flag.
- **Low Power Mode / battery cut-off**: no evidence found. [U]

`sleep 0` vs `disablesleep 1`: `sleep 0` turns off the idle timer only. It does nothing for the lid. [P man page + kernel]

Local observation, not a fault report: at 14:49 this Mac was on AC with `SleepDisabled 1`, and at 14:51 it was `0`. `-b` does not limit the flag to battery; the flag applies to all power sources while it is set.

---

## E. Recommendation for agent caffeine

1. **Keep `SleepDisabled` as the mechanism** for lid closed on battery. Nothing more reliable is available to third parties. The entitled assertion properties are Apple-only.
2. **Arm it earlier.** Set it when the agent works **and** the user enabled lid-closed mode, on AC as well as on battery (or at least as soon as the lid closes or the power source changes while armed). This removes the unplug-while-closed race. Use `-a` in the command; `-b` has no meaning for this setting.
3. **Verify.** After each set, read `SleepDisabled` from `IOPMrootDomain` and retry. Show the real state in the menu. If the read-back is wrong, say so.
4. **Treat it as dangerous state.** It survives app crash and reboot, and it blocks low-battery and thermal sleep in the kernel. Add: clear at launch if no work is active; a watchdog (LaunchAgent or the root helper) that clears it when the app is gone; battery floor (10-20 %); stop at `ProcessInfo.thermalState >= .serious`; a maximum time; and at the battery floor, clear the flag and then request sleep so the Mac does not die.
5. **Do not fight other writers.** If `SleepDisabled` is already 1 before we arm, do not clear it at the end (LidKeeper and oviron/Awake both handle this).
6. **Optional, no-root tier:** call `kPMSetClamshellSleepState(1)` for users who did not install the privileged part, and re-apply on power-source change, wake and a short timer. Label it "best effort". It also keeps normal low-battery sleep. Do not rely on it alone.
7. **Privilege path:** sudoers is fine today. Move to an `SMAppService` daemon when there is time: better first-run experience, clean uninstall, and it gives us the watchdog for point 4.
8. **Change the in-app note.** Replace "on Apple silicon `disablesleep` does not always hold" with what is true: the setting is global and survives restarts; the app checks it and restores it.
9. Keep holding `PreventUserIdleSystemSleep` (idle) and `PreventSystemSleep` (AC lid-closed dark wake) as now.
10. Check on hardware before release (a VM cannot test this): lid close on battery; unplug with lid closed; plug in with lid closed; external display plug/unplug; 30+ minutes closed; reboot with flag set; kill -9 the app with flag set.

---

## F. Sources

Primary (code, headers, man pages):

- XNU `iokit/Kernel/IOPMrootDomain.cpp`, `RootDomainUserClient.cpp`, `iokit/IOKit/pwr_mgt/IOPM.h`: https://github.com/apple-oss-distributions/xnu
- PowerManagement `pmconfigd/PMAssertions.c`, `pmconfigd/pmconfigd.m`, `pmconfigd/PMSettings.m`, `pmset/pmset.m`, `caffeinate/caffeinate.c`: https://github.com/apple-oss-distributions/PowerManagement
- IOKitUser `pwr_mgt.subproj/IOPMEnergyPrefs.c`, `IOPMLibPrivate.h`: https://github.com/apple-oss-distributions/IOKitUser
- `man caffeinate`, `man pmset`, `pmset -g`, `pmset -g assertions`, `pmset -g log`, `ioreg` on macOS 26.7.1 (read only)
- Claude Code 2.1.289 local binary (strings)
- Codex sleep inhibitor: https://github.com/openai/codex/tree/main/codex-rs/utils/sleep-inhibitor
- Amphetamine Power Protect: https://github.com/x74353/Amphetamine-Power-Protect
- Amphetamine resources: https://github.com/x74353/Amphetamine
- Amphetamine Enhancer: https://github.com/x74353/Amphetamine-Enhancer
- KeepingYouAwake: https://github.com/newmarcel/KeepingYouAwake
- NoSleep: https://github.com/integralpro/nosleep
- InsomniaX: https://github.com/semaja2/InsomniaX
- LidOn: https://github.com/jayden0903/LidOn
- Orexin: https://github.com/tompopham/Awake
- LidKeeper: https://github.com/BlueRaddish/LidKeeper
- LidSleepToggle: https://github.com/Sufxx/LidSleepToggle
- Sleepless: https://github.com/Aboudjem/Sleepless and https://github.com/mmavko/Sleepless
- Electronic Clam: https://github.com/kingsj0405/eclam
- Awake (oviron): https://github.com/oviron/Awake

Community:

- Claude Code issues: https://github.com/anthropics/claude-code/issues/21432 , https://github.com/anthropics/claude-code/issues/81832 , https://github.com/anthropics/claude-code/issues/45769
- Orca: https://github.com/stablyai/orca/issues/20194
- jetlink PR: https://github.com/zoompilot/jetlink/pull/10
- batt: https://github.com/charlie0129/batt/issues/149
- Tailscale: https://github.com/tailscale/tailscale/issues/20859
- BetterDisplay: https://github.com/waydabber/BetterDisplay/issues/4312
- clamshell.dev guide: https://clamshell.dev/guides/macbook-lid-closed-on-battery
- helmlet: https://helmlet.app/en/blog/keep-macbook-awake-lid-closed
- 9to5Mac (2026-06-12): https://9to5mac.com/2026/06/12/how-to-keep-your-mac-awake-even-when-your-macbook-lid-is-closed/
- SMAppService notes: https://theevilbit.github.io/posts/smappservice/
- Lungo: https://sindresorhus.com/lungo
- Apple Support, operating temperatures: https://support.apple.com/en-us/102336
- Apple Community, macOS 26 wake problem: https://discussions.apple.com/thread/256150505

Could not open (claims from these are marked [U]):

- https://pasqualepillitteri.it/en/news/779/disable-laptop-sleep-lid-close-ai-agents (socket error)
- https://forums.macrumors.com/threads/prevent-macbook-air-m2-sleep-when-lid-is-closed.2358380/ (HTTP 403)
- https://developer.apple.com/documentation/servicemanagement/smappservice (page body did not load)

Not examined: Jolt of Caffeine internals, Sleep Control Centre internals, Macs Fan Control, JetBrains, Docker Desktop, ChatGPT/Codex desktop app setting.
