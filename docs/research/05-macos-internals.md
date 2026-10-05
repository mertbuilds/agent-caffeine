# 05 - macOS internals for the agent caffeine detection engine

Date: 2026-10-05. Test machine: macOS 26.7.1 (25G241), arm64, Darwin 25.6.0, AC power, lid open.
All probes ran as the normal user (uid 501), no root, no entitlements, ad-hoc binaries from clang/swiftc.
Probes were throwaway and are deleted. Outputs below are exact, with paths and addresses removed.

Claim labels: **[proven-here]** = I ran it on this machine. **[primary]** = Apple source or SDK header that I read today.
**[unconfirmed]** = from memory or secondary write-ups, not verified today.

Primary sources read (apple-oss-distributions, `main` branch, and the local Xcode SDK):
- xnu `bsd/kern/proc_info.c`, `bsd/kern/kern_event.c`, `bsd/vfs/vfs_vnops.c`, `bsd/net/ntstat.c`, `bsd/kern/kern_sysctl.c`, `iokit/Kernel/IOPMrootDomain.cpp`
- IOKitUser `pwr_mgt.subproj/IOPMLibPrivate.h`; PowerManagement `pmconfigd/PMAssertions.c`
- SDK `IOKit/pwr_mgt/IOPMLib.h`, `sys/resource.h`, `sys/proc_info.h`, `Foundation/NSProcessInfo.h`
- Apple docs: App Nap (Energy Efficiency Guide), `es_new_client`

---

## 0. Headline findings

1. libproc gives everything `ps` gives, plus energy, instructions, disk bytes, wakeups, open files and sockets, for every same-user process, including helpers inside other apps. No TCC prompt. A full sweep of 979 pids took 1.9 ms. `ps` took 28 ms of wall time plus a fork/exec. [proven-here]
2. `/bin/ps` is setuid root. libproc from a normal app cannot read root-owned processes (EPERM). This does not matter for agents, which run as the user. [proven-here]
3. FSEvents reports a content change only when the writer closes the file. A file that a process keeps open and appends to (Codex rollout `.jsonl`, any SQLite `-wal`) produces no FSEvents event until close. kqueue `EVFILT_VNODE` and `stat` see every write at once. [proven-here + primary]
4. The mtime of `/dev/ttysNNN` moves on every write to the terminal. It is a free "agent printed output" signal with no TCC cost. [proven-here]
5. A third-party app cannot keep a MacBook awake with the lid closed on battery through assertions. The two keys that would do it need Apple-private entitlements. [primary]
6. `PROC_PIDFDSOCKETINFO` shows "an ESTABLISHED TCP connection to port 443 exists". It has no byte counters. Byte flow needs the private NetworkStatistics path. [proven-here + primary]
7. Claude Code's process name (`p_comm`) is its version number ("2.1.288"), not "claude". Match on the executable path or argv[0]. [proven-here]

---

## 1. Process enumeration and stats without `ps`

### 1.1 What works, and on whom

Probe targets: `claude` on a tty (pid 2422), a daemon `claude` (20909), `codex` engine inside `/Applications/ChatGPT.app` (25445), a Chromium renderer inside ChatGPT.app (69955), and root processes (1, 519).

| Call | Same-user CLI | Other app's helper (same user) | Root process |
|---|---|---|---|
| `proc_listpids(PROC_ALL_PIDS)` | yes | yes | yes (lists pid) |
| `sysctl CTL_KERN, KERN_PROC, KERN_PROC_ALL` (`kinfo_proc`) | yes | yes | yes |
| `proc_pidpath` | yes | yes | yes |
| `proc_pidinfo PROC_PIDTBSDINFO` | yes | yes | **EPERM** |
| `proc_pidinfo PROC_PIDTASKINFO` | yes | yes | **EPERM** |
| `proc_pid_rusage RUSAGE_INFO_V6` | yes | yes | **EPERM** |
| `sysctl KERN_PROCARGS2` | yes | yes | **EINVAL** |
| `proc_pidinfo PROC_PIDLISTFDS` + `proc_pidfdinfo` | yes | yes | **EPERM** |
| `responsibility_get_pid_responsible_for_pid` | yes | yes | returns -1 |
| `proc_pidinfo` flavor 20 (`PROC_PIDCOALITIONINFO`) | yes | yes | yes |

All rows [proven-here]. The rule in the kernel [primary, `proc_info.c`]: `proc_security_policy(..., CHECK_SAME_USER)` compares caller uid with target uid and returns EPERM on mismatch. Only five flavors skip the check: `PROC_PIDT_SHORTBSDINFO`, `PROC_PIDUNIQIDENTIFIERINFO`, `PROC_PIDPATHINFO`, `PROC_PIDCOALITIONINFO`, `PROC_PIDPLATFORMINFO`. `proc_pid_rusage` uses the same check. There is no "responsible app" or TCC gate: the only gate is uid (plus a MAC hook, `mac_proc_check_proc_info`, that the sandbox uses; a non-sandboxed app passes).

Exact output, claude on a tty:

```
== pid 2422
proc_pidpath: ~/.local/share/claude/versions/2.1.288 (ok)
bsdinfo: uid=501 ppid=2514 pgid=2422 e_tdev=0x10000001 tty=ttys001 e_tpgid=2422 fg=YES start=1791022342.515921 comm=2.1.288 status=2 flags=0x4040d0 nfiles=100
tty stat: mode=620 uid=501 atime=1791199411 mtime=1791199531 ctime=1791199531 now=1791201106
taskinfo: user_raw=118662164199 sys_raw=16152338585 -> cpu=5617.27s (x timebase 41.6667) threads=20 running=0 csw=45037399 syscalls_unix=112507455 mach=15006076 rss=777MB
rusage V6: user=4944.26s sys=673.01s instr=15153293819393 cycles=13897552748674 energy_nj=5585984338040 billed_nj=160985917 penergy_nj=4537525412554 diskread=9355935744 diskwrite=1373130752 logical_writes=1649155475 pkg_wakeups=84810 intr_wakeups=4065327 qos: def=0.00 bg=0.00 util=0.00 ui=0.05 uin=0.00 maint=0.00 footprint=529MB
responsible pid: 2422 (itself)
coalition: resource=1481 jetsam=1482
KERN_PROCARGS2: ok bytes=3116 argc=4 exec_path=~/.local/bin/claude
  fd 0,1,2,4,5,10,11 TTY /dev/ttys001
  fd 14 TCP state=4(ESTABLISHED) rport=443 lport=54744 remote=<public v4> rcvbuf_cc=0 sndbuf_cc=0
fds: total=20 vnode=7 socket=10 pipe=0 kqueue=3 other_unix_sock=9
```

`ps` showed TIME 93:37.24 for this pid = 5617 s. The match proves the unit conversion below.

Exact output, Codex engine inside ChatGPT.app:

```
== pid 25445
proc_pidpath: /Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex (ok)
bsdinfo: uid=501 ppid=25328 pgid=25328 e_tdev=0xffffffff tty=- e_tpgid=0 fg=no start=1790950219.889062 comm=codex status=2 flags=0x1404010 nfiles=300
taskinfo: ... -> cpu=172.74s threads=28 running=0 csw=2607785 syscalls_unix=9689441 mach=455963 rss=270MB
rusage V6: user=118.05s sys=54.69s instr=908017175492 cycles=428404019709 energy_nj=220658581065 billed_nj=5713013241 diskread=1280675840 diskwrite=1152413696 logical_writes=2018059768 pkg_wakeups=2676 intr_wakeups=156798 qos: bg=0.05 (rest 0) footprint=327MB
responsible pid: 25328 /Applications/ChatGPT.app/Contents/MacOS/ChatGPT
coalition: resource=107750 jetsam=107751
KERN_PROCARGS2: ok bytes=4324 argc=9
  fd 10 VNODE .sqlite size=23056384    fd 11 VNODE .sqlite-wal size=4494952    fd 12 VNODE .sqlite-shm
  fd 13 TCP state=4(ESTABLISHED) rport=443 lport=55046 remote=<public v4> rcvbuf_cc=0 sndbuf_cc=0
  fd 20,32,35,38,40,69,92,100,146 VNODE .jsonl (offset == size, openflags=0x1000b = read/write + O_APPEND)
fds: total=106 vnode=28 socket=11 pipe=63 kqueue=3
```

Chromium renderer inside ChatGPT.app (69955): all calls succeed. QoS breakdown is populated there (`ui=101.64s uin=412.84s bg=0.85s`), responsible pid = ChatGPT main, same coalition 107750.

Root (pid 1 and 519): `proc_pidpath` ok, coalition ok, everything else `Operation not permitted`; `KERN_PROCARGS2` gives `Invalid argument`.

### 1.2 Field notes

- **CPU time units.** `pti_total_user/system` and `ri_user_time/system_time` are in mach absolute time ticks, not nanoseconds. On Apple silicon multiply by `mach_timebase_info` (125/3 = 41.667 ns per tick here). On Intel the ratio is 1, so code without the conversion works on Intel and is wrong by 41x on Apple silicon. [proven-here: raw x 41.667 matches `ps` TIME]
- **`rusage_info_v6` fields** [primary, SDK `sys/resource.h`; `RUSAGE_INFO_CURRENT` = V6]: `ri_user_time`, `ri_system_time`, `ri_pkg_idle_wkups`, `ri_interrupt_wkups`, `ri_pageins`, `ri_phys_footprint`, `ri_proc_start_abstime`, `ri_child_*`, `ri_diskio_bytesread`, `ri_diskio_byteswritten`, `ri_cpu_time_qos_{default,maintenance,background,utility,legacy,user_initiated,user_interactive}`, `ri_billed_system_time`, `ri_serviced_system_time`, `ri_logical_writes`, `ri_instructions`, `ri_cycles`, `ri_billed_energy`, `ri_serviced_energy`, `ri_runnable_time`, `ri_user_ptime`, `ri_system_ptime` (P-core time), `ri_pinstructions`, `ri_pcycles`, `ri_energy_nj`, `ri_penergy_nj`, neural footprint fields. **There are no network counters in any rusage version.**
- **Energy.** `ri_energy_nj` is populated on Apple silicon [proven-here]. Delta nanojoules / delta seconds = watts for that process. It is the most honest "is it working" number, because it is independent of core type (E versus P).
- **Instructions and cycles** are a better work measure than CPU time when the process runs on E-cores at low frequency.
- **Disk.** `ri_diskio_byteswritten` counts bytes that reached the device. `ri_logical_writes` counts bytes the process wrote to the file system layer (includes cached writes). Use `ri_logical_writes` delta as the "is writing" signal: it moves at write time, not at flush time. [primary for field meaning; values proven-here]
- **QoS breakdown** is zero for CLI tools (their threads have no QoS class; time lands in none of the listed buckets). It works for apps and Chromium helpers. Do not build logic on it for CLIs. [proven-here]
- **Wakeups.** `ri_interrupt_wkups` delta shows a process that is "alive and polling" with tiny CPU use.
- **`pti_numrunning`** (threads on a core right now) is an instantaneous sample; it was 0 for all targets. Deltas of cumulative counters are better.
- **`pti_csw`, `pti_syscalls_unix`** deltas: cheap activity indicators that move when CPU time is below your 3 percent threshold.
- **Process identity.** pid reuse is real. Key each process as (pid, `pbi_start_tvsec.tvusec`). `PROC_PIDUNIQIDENTIFIERINFO` also gives a 64-bit unique id that is never reused. [primary]
- **Name.** `pbi_comm` / `ucomm` is the basename of the resolved executable (16 chars max). Claude Code installs as `versions/2.1.288`, so comm = `2.1.288` [proven-here]. Use `proc_pidpath` (contains `/claude/versions/`) or `KERN_PROCARGS2` exec_path (`~/.local/bin/claude`, the symlink as invoked).
- **argv.** `KERN_PROCARGS2` layout: `int argc`, exec path, NUL padding, argv strings, then env strings. The kernel refuses other users' processes (EINVAL) [proven-here + primary]. It hides environment variables of hardened-runtime (`cs_restricted`) targets unless the caller is the target or SIP is off [primary, `kern_sysctl.c` `sysctl_procargsx`]. argv stays readable.
- **Zombies** have no args; `KERN_PROCARGS2` fails. Handle errors per pid.
- **Tree.** `pbi_ppid` gives the parent. Build the subtree in memory from one sweep. `proc_listchildpids(pid)` exists but is one syscall per parent.
- **Responsible pid.** `responsibility_get_pid_responsible_for_pid` is exported from libSystem (libquarantine) but is in no public header: declare it yourself. It maps the Codex engine and the renderer to the ChatGPT main pid [proven-here]. Terminal-hosted claude returned itself here, because the host (`herdr`) spawned it disclaimed or as its own responsible process. So "responsible pid" answers "which app owns this helper" for GUI apps, and is not reliable for "which terminal".
- **Coalitions.** Flavor 20 returns resource and jetsam coalition ids. All ChatGPT.app children share coalition 107750; all terminal children share 1481 (the terminal's). Coalition id is the grouping the kernel and Activity Monitor use for per-app energy. It is a private flavor (not in the SDK header; struct = `uint64_t coalition_id[2]; uint64_t reserved[3]`). Stable for years, but private. [proven-here]. Reading coalition resource totals (`coalition_info`) needs root [unconfirmed].
- **Foreground job test.** `pbi_pgid == e_tpgid` and `e_tdev != -1` means the process is in the foreground process group of its controlling terminal. Proven: claude 2422 `pgid=2422 e_tpgid=2422 fg=YES`; its parent zsh has pgid 2514, not foreground. A claude that the user suspended with Ctrl-Z, or that runs under `&`, fails this test. `pbi_status` gives SRUN(2) / SSTOP(4).
- **tty name.** `devname(e_tdev, S_IFCHR)` gives `ttys001`.

### 1.3 Cost

```
bench: pids=979 rusage ok=662 fail=317 bsdinfo ok=660 mine=660 elapsed=1.931 ms
bench: sysctl KERN_PROC_ALL entries=979 elapsed=0.199 ms
/bin/ps -axww -o pid=,ppid=,time=,ucomm=,args=   0.028 s total (0.01 user + 0.02 sys), plus fork/exec/pipe/parse in the app
```

One `sysctl KERN_PROC_ALL` (0.2 ms) returns pid, ppid, pgid, tpgid, tdev, uid, start time, comm for every process. Then call `proc_pid_rusage` only on the tracked subtree (about 3 microseconds each). A 2-second poll of 50 tracked pids costs well under 0.01 percent of a core. [proven-here]

### 1.4 Sketch

```swift
// 1. cheap census
var mib = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]; var len = 0
sysctl(&mib, 3, nil, &len, nil, 0)
let buf = UnsafeMutableRawPointer.allocate(byteCount: len + 65536, alignment: 8)   // table can grow
sysctl(&mib, 3, buf, &len, nil, 0)            // [kinfo_proc]: kp_proc.p_pid, kp_eproc.e_ppid, e_pgid, e_tpgid, e_tdev, e_ucred.cr_uid, p_starttime, p_comm

// 2. per tracked pid
var ri = rusage_info_v6()
withUnsafeMutablePointer(to: &ri) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) } }
// fall back to RUSAGE_INFO_V4 on macOS 13 if V6 returns EINVAL (V6 needs macOS 13+ SDK structs; check errno)
var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
let cpuNs = (ri.ri_user_time + ri.ri_system_time) * UInt64(tb.numer) / UInt64(tb.denom)
// signals: delta cpuNs, delta ri_energy_nj, delta ri_instructions, delta ri_logical_writes, delta ri_interrupt_wkups
```

---

## 2. Process lifecycle events

| Mechanism | What it gives | Unprivileged | Notes |
|---|---|---|---|
| kqueue `EVFILT_PROC` / `DispatchSource.makeProcessSource` | NOTE_EXIT, NOTE_FORK, NOTE_EXEC, NOTE_SIGNAL per watched pid | yes, any pid (also root's) | Does not give the child pid. No "watch all processes" mode. |
| `NSWorkspace.didLaunchApplicationNotification` / `didTerminate` | GUI app launch and quit with bundle id and pid | yes, no TCC | Only apps registered with LaunchServices. Never CLI tools or helpers. |
| `NSRunningApplication` KVO, `NSWorkspace.runningApplications` | Same set, polled or observed | yes | Same limit. |
| Endpoint Security (`ES_EVENT_TYPE_NOTIFY_EXEC/FORK/EXIT`) | Every exec, fork, exit system-wide, with argv | **no** | Needs `com.apple.developer.endpoint-security.client` (Apple must grant it), a system extension or root daemon, and user approval in Full Disk Access [primary, Apple docs `es_new_client`]. Not an option for this app. |
| kdebug / ktrace / `fs_usage` / `dtrace` | Kernel trace stream | **no** | Root only; dtrace also needs SIP relaxations. [unconfirmed today; long-standing] |
| `sysctl KERN_PROC` diff | New and gone pids | yes | 0.2 ms per poll. This is the practical "exec event" source. |

Proof [proven-here]. Target was an orphan (reparented to launchd), so not my child:

```
orphan target pid=37930 ppid now=1
register non-child same-user pid=37930 fflags=0xe0000000 -> ok
register root launchd pid=1 fflags=0xe0000000 -> ok
register other app helper pid=25445 (codex in ChatGPT.app) -> ok
event pid=37930 fflags=0x40000000 FORK data=0
event pid=37930 fflags=0x20000000 EXEC data=0
event pid=37930 fflags=0x80000000 EXIT data=0
```

Rules from `kern_event.c filt_procattach` [primary]:
- `NOTE_TRACK`, `NOTE_TRACKERR`, `NOTE_CHILD` return ENOTSUP. You cannot follow children automatically. On NOTE_FORK, re-scan children (`proc_listchildpids` or the sysctl census) and add a source for each.
- `NOTE_EXIT | NOTE_EXITSTATUS` needs the caller to be the parent, the tracer, or allowed to signal the target. Plain `NOTE_EXIT` has no check.
- Registration for a pid that is gone returns ESRCH: handle the race between census and registration.

Use: one process source per tracked agent pid for instant exit detection (release the assertion in milliseconds, not at the next poll), and NOTE_FORK as a free "agent started a tool" activity pulse. Cost is zero while nothing happens.

```swift
let src = DispatchSource.makeProcessSource(identifier: pid, eventMask: [.exit, .fork, .exec], queue: q)
src.setEventHandler { let e = src.data; if e.contains(.exit) { engine.gone(pid) } else { engine.pulse(pid, .fork) } }
src.resume()
```

---

## 3. File activity

### 3.1 The FSEvents close rule

Probe: FSEvents stream (`kFSEventStreamCreateFlagFileEvents | NoDefer`, latency 0.1 s) on a temp directory, plus a `DispatchSource.makeFileSystemObjectSource` on the file, plus `stat`. Exact output [proven-here]:

```
[ 1.01] WRITE #1 on held-open fd (no close)
[ 1.01] EVFILT_VNODE held.jsonl mask=6 (write=2 extend=4)
[ 2.51]   stat: size=5 mtime_age=1.51s
[ 2.51] WRITE #2 on held-open fd (no close)
[ 2.51] EVFILT_VNODE held.jsonl mask=6
[ 4.02] WRITE #3 on held-open fd (no close)
[ 4.02] EVFILT_VNODE held.jsonl mask=6
[ 5.52] FSYNC                                   <- no FSEvents
[ 7.02] CLOSE writer fd
[ 7.03] FSEvents held.jsonl ["Modified"]        <- first FSEvents event, 6 s after the first write
[ 8.52] append via open-write-close (appendFile style)
[ 8.52] EVFILT_VNODE held.jsonl mask=6
[ 8.53] FSEvents held.jsonl ["Modified"]        <- 10 ms latency when the writer closes
[ 9.52] --- sqlite WAL, one connection held open, 3 inserts 1.5 s apart
[ 9.55] FSEvents s.sqlite ["Created"]  s.sqlite-wal ["Created"]  s.sqlite-shm ["Created","InodeMeta"]
[15.55] sqlite connection closed
[15.56] FSEvents s.sqlite-shm / s.sqlite-wal / s.sqlite ["Modified","InodeMeta"]   <- nothing for the 3 inserts
```

Kernel reason [primary, `vfs_vnops.c vn_close`]: `if (flags & FWASWRITTEN) add_fsevent(FSE_CONTENT_MODIFIED, ...)`. The content-modified event is posted at close, once, if the descriptor was written.

Consequences:
- Claude Code transcripts work with FSEvents today because Claude Code appends with open-write-close. That is an implementation detail of the agent, not a guarantee.
- Codex keeps its rollout `.jsonl` files open with O_APPEND (9 such fds seen on pid 25445, offset == size). FSEvents will be silent during a Codex turn. Use `EVFILT_VNODE` or poll `stat` size.
- SQLite WAL writes (Cursor, ChatGPT, Codex state databases) are invisible to FSEvents until the connection closes or the WAL file is truncated/renamed at checkpoint. `stat` of the `-wal` file shows size and mtime changes at once. Writes into the `-shm` file go through mmap and update nothing reliably.
- FSEvents coalesces: several changes to one path inside the latency window arrive as one event with OR-ed flags; flags also accumulate across history for the same file ("Created" kept appearing later). Treat an event as "something happened to this path", then `stat`.
- FSEvents latency parameter: seconds to wait to batch. `NoDefer` delivers the first event at once, then batches. Measured end-to-end latency after close: about 10 ms.
- FSEvents needs no TCC prompt for `~/.claude`, `~/.codex`, `~/Library/Application Support/<app>` in a non-sandboxed app. Paths under Desktop, Documents, Downloads, iCloud, and other apps' sandbox containers (`~/Library/Containers/...`) trigger TCC prompts or silent denials on first file access (macOS 14+ "access data from other apps" prompt for containers). [unconfirmed today; known behaviour]

### 3.2 Options

| Mechanism | Sees held-open appends | Latency | Cost | Limit |
|---|---|---|---|---|
| FSEvents (file events) | **no, only at close** | ~10 ms after close + your latency value | near zero idle; one fseventsd client | Whole directory trees, no fd per file |
| kqueue `EVFILT_VNODE` / `makeFileSystemObjectSource` (`.write .extend .delete .rename`) | yes, each write | immediate | one fd per file (open with `O_EVTONLY`) | Must discover files first; re-open after rename/delete; fd limit 256 by default soft limit |
| `stat` poll of known files (size, mtime) | yes | your poll interval | ~1 microsecond per file | Polling |
| `PROC_PIDLISTFDS` + `PROC_PIDFDVNODEPATHINFO` | n/a: tells which files the agent has open, with current offset and size | poll | ~20 microseconds per process | Same-user only |
| `ri_logical_writes` / `ri_diskio_byteswritten` delta | yes, in aggregate | poll | free with the rusage call | No file names |

Recommended pattern: FSEvents on the session directories to discover new transcript files (creation always fires). For each active session file, attach an `EVFILT_VNODE` source. For agents with no known transcript, use `PROC_PIDLISTFDS` once to find `.jsonl` / `-wal` files the agent holds open, then watch those. `vip_vi.vi_stat.vst_size` and `fi_offset` from the fd info are themselves a growth signal without touching the file.

```swift
let fd = open(path, O_EVTONLY)
let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: q)
s.setEventHandler { engine.pulse(session, .transcriptWrite) }   // then read new bytes if you parse
s.setCancelHandler { close(fd) }; s.resume()
```

---

## 4. Network activity per process

| Mechanism | Tells us | Unprivileged | Cost |
|---|---|---|---|
| `PROC_PIDLISTFDS` + `proc_pidfdinfo(PROC_PIDFDSOCKETINFO)` | Per socket: family, TCP state (`tcpsi_state`, 4 = ESTABLISHED), local and remote address and port, bytes queued in send/receive buffers right now (`soi_snd.sbi_cc`, `soi_rcv.sbi_cc`) | yes, same user, incl. other apps' helpers [proven-here] | ~20-50 microseconds per process |
| rusage | nothing: no network fields in V0-V6 [primary] | - | - |
| NetworkStatistics.framework (`NStatManager`, private) / kernel control `com.apple.network.statistics` | Cumulative rx/tx bytes and packets per socket and per process, live updates | yes on macOS: `net.statistics_privcheck: 0` [proven-here]; xnu `ntstat.c` sets `nstat_privcheck = 0` for `XNU_TARGET_OS_OSX` [primary]. `nettop` has `com.apple.private.network.statistics` but ran its per-process query without root here. | Private API. A subscription is event-driven and cheap; no notarization block, but the API can change. |
| `nettop -P -L 1 -x -J bytes_in,bytes_out -p <pid>` | Same data as text | yes [proven-here: `codex.25445,4150,15472`] | Bad: one 2-sample run took 16 s wall and 1.07 s system CPU. Debug aid only. |
| `lsof -nP -a -p <pid> -i` | Socket list as text | yes | 39 ms per run; it is libproc underneath. Do not spawn it. |
| Network Extension content filter / `NEFilterDataProvider` | Per-flow bytes with process identity | needs entitlement + system extension + user approval | Not suitable. |

Answer to "can we tell that a process has a live HTTPS stream and bytes are flowing":
- "Has a live TCP connection to :443": **yes**, public API, proven. Claude 2422 showed `fd 14 TCP ESTABLISHED rport=443`; the Codex engine showed `fd 13 TCP ESTABLISHED rport=443`.
- "Bytes are flowing": **not from libproc.** `sbi_cc` is the instantaneous queue depth (0 in both samples, because readers drain fast). Options: (a) NetworkStatistics private framework for real byte deltas; (b) proxy signals: CPU and wakeup deltas of the process while the socket exists (TLS decrypt of a token stream costs CPU and interrupt wakeups), the socket's local port changing (a new request = new connection or HTTP/2 stream reuse, so weak), and transcript growth.
- Caveats: HTTP/2 keep-alive connections stay ESTABLISHED for minutes after a stream ends, so "socket exists" alone over-reports work. Electron apps do network I/O in the "Network Service" utility helper, not in the renderer (renderer 69955 had 0 sockets) and not always in the main process. QUIC uses UDP: `soi_kind == SOCKINFO_IN`, no TCP state.
- A waiting-on-model agent (request sent, no tokens yet, CPU near zero) is the case CPU sampling misses. An ESTABLISHED :443 socket plus a recent transcript "user/tool_result" record is the cheap public-API way to cover it.

```c
int n = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, size) / sizeof(struct proc_fdinfo);
for each fd where proc_fdtype == PROX_FDTYPE_SOCKET:
  struct socket_fdinfo s; proc_pidfdinfo(pid, fd, PROC_PIDFDSOCKETINFO, &s, sizeof s);
  if (s.psi.soi_kind == SOCKINFO_TCP) {
     state = s.psi.soi_proto.pri_tcp.tcpsi_state;                       // TCPS_ESTABLISHED == 4
     rport = ntohs(s.psi.soi_proto.pri_tcp.tcpsi_ini.insi_fport);       // 443
  }
```

---

## 5. Terminal and pty

- **`stat("/dev/ttysNNN")` works for same-user ttys** (mode 620, owner = user) and its times are live [proven-here]. Four samples 2 s apart on the tty of a TUI that repaints constantly: mtime `...122, ...124, ...125, ...128` (tracks wall clock). Idle ttys kept mtimes hours old. Meaning: **mtime = last write to the slave side = program output**; **atime = last read = the program consumed keyboard input**. This is what `w` uses for idle time. So `now - mtime` = "seconds since the agent last printed", `now - atime` = "seconds since the user last typed into this terminal".
- Cost: one `stat` per tty, about 1 microsecond. No TCC. Works through tmux/herdr-style multiplexers, because each pane has its own pty and the agent's `e_tdev` points at the inner one.
- Limits: a spinner or a status-line clock updates mtime while the agent only waits (Claude Code's "thinking" spinner writes about every 100 ms). So tty mtime says "alive and animating", not "making progress"; a permission prompt with no animation makes it go quiet, which is itself useful ("waiting for the user"). Resolution is 1 s in practice. kqueue on the tty device node from an outside process was not tested [unconfirmed]; poll instead.
- **Reading another process's pty content: not possible** without being the master side holder. Opening the slave from outside and reading would steal input. Do not do it. `task_for_pid` is not available (section 9).
- **Terminal window title via Accessibility** (`AXUIElementCopyAttributeValue(kAXTitleAttribute)`): needs the Accessibility TCC grant (System Settings prompt, user must toggle manually; grant is tied to the code signature). Gives the title that the agent set through OSC 0/2, for example Claude Code's status glyph. Cost: an IPC round trip to the terminal app per read. `CGWindowListCopyWindowInfo` returns window titles of other apps only with the Screen Recording grant (since macOS 10.15). Both are heavy consent for a small signal. Not recommended as a base signal.
- **OSC 9 / 777 / 99 notifications and OSC 133 prompt marks** go to the terminal emulator, not to the OS. Another app cannot see them unless the terminal re-publishes them (for example as a `UNUserNotification`, which other apps cannot read either). A hook inside the agent (Claude Code hooks, Codex `notify`) is the supported way to get those state changes; that is a different research track.
- `ttyskeepawake` in `pmset -g` (value 1 here) means the system already refuses idle sleep while a remote (ssh) tty had recent input; it does not cover local ptys with output only. [unconfirmed detail]

---

## 6. Power

### 6.1 Reading state [all proven-here, unprivileged, no TCC]

```
IOPMCopyAssertionsByProcess ret=0
 pid=532  type=PreventUserIdleSystemSleep name=Powerd - Prevent sleep while display is on
 pid=9735 type=PreventUserIdleSystemSleep name=caffeinagent: agentWorking  keys=[AllowsDeviceRestart,AssertLevel,AssertName,AssertPID,AssertStartWhen,AssertType,AssertionId,AssertionTrueType,GlobalUniqueID,Process Name]
 pid=9735 type=PreventSystemSleep         name=caffeinagent: agentWorking
 pid=38214 type=PreventUserIdleSystemSleep name=caffeinate command-line tool timeoutLeft=300 (+ Details, HumanReadableReason, TimeoutAction, TimeoutSeconds)
 pid=591  type=UserIsActive name=com.apple.iohideventsystem.queue.tickle ...
 pid=83689 type=SystemIsActive name=NSURLSessionTask <uuid> timeoutLeft=10800
IOPMCopyAssertionsStatus ret=0
  ["UserIsActive": 1, "PreventUserIdleSystemSleep": 1, "SystemIsActive": 1, "EnableIdleSleep": 1, "PreventSystemSleep": 1]

ioreg -r -k AppleClamshellState -d 1:
  +-o IOPMrootDomain  <class IOPMrootDomain, ...>
      "IOPMSystemSleepType" = 7
      "AppleClamshellCausesSleep" = Yes
      "AppleClamshellState" = No
      "SleepDisabled" = No
(same through IORegistryEntryCreateCFProperty on the IOPMrootDomain service; 1000 reads = 2.5 ms)

HID idle anyInput: 0.53 s   keyDown: 27.8 s   mouseMoved: 2.37 s      (CGEventSource.secondsSinceLastEventType)
ioreg IOHIDSystem "HIDIdleTime" = 5982812041 (nanoseconds)
CGSessionCopyCurrentDictionary: CGSSessionScreenIsLocked absent (= unlocked), kCGSSessionOnConsoleKey=1
CGDisplayIsAsleep(main)=0
thermalState=0 (nominal)  isLowPowerModeEnabled=false
IOPSGetProvidingPowerSourceType=AC Power; battery cap=100/100 state=AC Power charging=0
pmset -g: "sleep 0 (sleep prevented by powerd, sharingd, caffeinate, caffeinagent, caffeinagent)"
```

Uses:
- `IOPMCopyAssertionsByProcess` shows who else keeps the Mac awake (and proves your own assertion is live). A browser or another agent tool that already holds `PreventUserIdleSystemSleep` is itself an activity hint. Note "Powerd - Prevent sleep while display is on": while the display is on, the system will not idle-sleep anyway. Your assertion matters only after the display sleeps.
- Clamshell: `AppleClamshellState` (lid closed now) and `AppleClamshellCausesSleep` (would closing it sleep the Mac; No in desktop mode = external display + power). Subscribe with `IOServiceAddInterestNotification(rootDomain, kIOGeneralInterest)` and handle `kIOPMMessageClamshellStateChange` instead of polling [unconfirmed for a non-root client; polling at 2.5 microseconds per read is also fine].
- Power source changes: `IOPSNotificationCreateRunLoopSource` (any change) or `IOPSCreateLimitedPowerNotification` (AC/battery flips only), or the notify(3) key `com.apple.system.powersources.source`. Event-driven, no cost. [primary, IOPSKeys.h; not run today]
- Thermal: `ProcessInfo.thermalStateDidChangeNotification`. Low Power Mode: `NSProcessInfoPowerStateDidChange` (macOS 12+).

### 6.2 Holding the Mac awake

`IOPMAssertionCreateWithProperties` / `IOPMAssertionCreateWithName`. No entitlement, works under hardened runtime. Types that matter [primary, SDK `IOPMLib.h` + powerd `PMAssertions.c`]:

| Type | Effect | On battery | Lid closed |
|---|---|---|---|
| `kIOPMAssertPreventUserIdleSystemSleep` ("PreventUserIdleSystemSleep") | Blocks idle sleep. Display may still dim and sleep. Header: "The system may still sleep for lid close, Apple menu, low battery, or other sleep reasons. This assertion has no effect if the system is in Dark Wake." | honoured | **no effect** |
| `kIOPMAssertPreventUserIdleDisplaySleep` | Keeps the display on (and so the system) | honoured | no effect |
| `kIOPMAssertionTypePreventSystemSleep` ("PreventSystemSleep", what `caffeinate -s` uses) | Blocks demand sleep too: the system goes to dark wake, not sleep. powerd flags the type `kAssertionTypeNotValidOnBatt`. The public header calls the old constant deprecated; powerd still implements it. | **ignored on battery** unless `kIOPMAssertionAppliesToLimitedPowerKey = true`, and that key needs entitlement `com.apple.private.iokit.assertonbattery` (powerd logs "Pid N is not privileged to set property") | On AC: lid close ends in DarkWake, system keeps running. On battery: sleeps. |
| `kIOPMAssertionTypeNoIdleSleep` ("NoIdleSleepAssertion") | Deprecated alias of PreventUserIdleSystemSleep (10.7) | same | same |
| `kIOPMAssertNetworkClientActive` | Keeps system awake in dark or full wake on AC; on battery only blocks idle sleep | partial | no |
| `IOPMAssertionDeclareUserActivity` | Wakes and keeps the display on like a key press, with a built-in timeout | honoured | no |
| `kIOPMAssertionAppliesOnLidClose` (private key) | Would hold through lid close | - | needs `com.apple.private.iokit.assertonlidclose` |

Evidence from this machine's `pmset -g log`, while caffeinagent held both types [proven-here, observational]:

```
2026-10-05 09:17:17 Entering DarkWake state due to 'Clamshell Sleep':TCPKeepAlive=active Using AC (Charge:100%)
2026-10-05 09:18:53 Entering Sleep state due to 'Clamshell Sleep':TCPKeepAlive=active Using Batt (Charge:100%)
Sleep reasons in the log: 291 Maintenance Sleep (Batt), 17 Maintenance Sleep (AC), 13 Sleep Service Back to Sleep, 8 Clamshell Sleep (Batt), 1 Idle Sleep (Batt)
```

So: lid closed on AC + `PreventSystemSleep` = the Mac stays in DarkWake (CPU and network run, display off, agents keep working). Lid closed on battery = real sleep; no public assertion prevents it. The only ways around it are `sudo pmset -a disablesleep 1` (root; sets `SleepDisabled`, visible in the rootDomain properties above) or desktop mode. `IOPMrootDomain.cpp`: `shouldSleepOnClamshellClosed = !clamshellDisabled && !(desktopMode && acAdaptorConnected) && !clamshellSleepDisableMask` [primary].

Assertion properties worth using:
- `kIOPMAssertionTimeoutKey` + `kIOPMAssertionTimeoutActionKey` (`TimeoutActionRelease` / `TurnOff` / `Log`): a dead-man switch. Create with a 60-120 s timeout and re-arm with `IOPMAssertionSetProperty` on each "working" verdict. If the app hangs or crashes, the Mac sleeps. (powerd also drops all assertions of a process when it exits.)
- `kIOPMAssertionNameKey`, `kIOPMAssertionDetailsKey`, `kIOPMAssertionHumanReadableReasonKey`: shown in `pmset -g assertions` and Activity Monitor. Put the agent name in Details for free debugging.
- One assertion, toggled with `kIOPMAssertionLevelKey` on/off, or create/release: both are a Mach IPC to powerd (tens of microseconds). Do not create one per agent.

`ProcessInfo.beginActivity(options:reason:)` [primary, `NSProcessInfo.h`]: `.idleSystemSleepDisabled` takes a `PreventUserIdleSystemSleep` assertion for you (seen in `pmset -g assertions` under the process). `.userInitiated` = that plus sudden/automatic termination disabled plus App Nap off. `.userInitiatedAllowingIdleSystemSleep` = App Nap off **without** blocking sleep: the right flag to keep the detector's timers honest while no agent works. It cannot express `PreventSystemSleep`.

### 6.3 Sleep notifications and veto

`IORegisterForSystemPower` (or `NSWorkspace.willSleepNotification` / `didWakeNotification` for the simple case) [primary, SDK `IOPMLib.h`]:
- `kIOMessageCanSystemSleep`: "the system is pondering an idle sleep". The app must answer with `IOAllowPowerChange` or `IOCancelPowerChange`. **`IOCancelPowerChange` vetoes the idle sleep.** The idle timer runs again and asks again later. No answer = the system proceeds after 30 s.
- `kIOMessageSystemWillSleep`: "non-abortable sleep" (lid close, Apple menu, low battery, forced). The app must call `IOAllowPowerChange`; if it does not, "the sleep will continue anyway after a 30 second timeout". Delaying up to 30 s is all an app can do. It cannot cancel.
- `kIOMessageSystemWillNotSleep`: someone vetoed.
- `kIOMessageSystemWillPowerOn` / `HasPoweredOn`: wake; do not acknowledge.

So an app **can veto idle sleep** (this is the pre-assertion mechanism; an assertion is cleaner because it shows in `pmset`), and **cannot veto clamshell or user-requested sleep**. The 30 s window on WillSleep is useful for one thing: a last look ("is an agent mid-turn?") to log or notify before the Mac sleeps. Clients that time out repeatedly get skipped (`ackTimeoutCnt >= 3` in `IOPMrootDomain.cpp`) [primary].

After wake, reset all deltas: `mach_absolute_time` does not advance during sleep but wall clock does, and CPU deltas across a sleep are meaningless.

### 6.4 Dark wake

Dark wake = CPU, disk, network on; display and audio off; user-level apps run with normal scheduling but the system is counting down to return to sleep. Entered for Power Nap, TCP keepalive, push, and on lid close under `PreventSystemSleep` on AC. Log lines above show `DarkWake from Deep Idle ... 45 secs` every few minutes on battery ("Maintenance Sleep" 291 times): each is a window where your app, and the agents, run for a short time. `PreventUserIdleSystemSleep` "has no effect if the system is in Dark Wake" [primary]: an idle-type assertion cannot turn a dark wake into staying awake; `PreventSystemSleep` on AC can hold it. An app can detect it: `IOPMrootDomain` capability flags via `IOPMConnection` (private) or simply "display asleep + `kIOMessageSystemWillPowerOn` without `HasPoweredOn` to full" [unconfirmed]. Practical rule: on wake notifications, re-evaluate at once rather than waiting for the next timer.

### 6.5 Debug aids

- `pmset -g assertions` (snapshot), `pmset -g assertionslog` (live stream, never returns: do not call it from the app or a script without a kill), `pmset -g log` (history of sleeps, wakes, dark wakes with reasons; a full read takes seconds), `pmset -g` (current settings and who prevents sleep), `log show --predicate 'process == "powerd"'`.

---

## 7. User presence signals [proven-here unless marked]

| Signal | API | Cost / consent |
|---|---|---|
| HID idle seconds | `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)`; per type (keyDown, mouseMoved) also works. IORegistry `IOHIDSystem` / `HIDIdleTime` (ns) is the same counter. | Microseconds. No TCC (reading idle time is not event tapping). |
| Screen locked | `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]` (key absent when unlocked). Events: `DistributedNotificationCenter` `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` [unconfirmed today; undocumented but long-lived]. | Free. |
| Display asleep | `CGDisplayIsAsleep(CGMainDisplayID())`; events `NSWorkspace.screensDidSleepNotification` / `screensDidWakeNotification`. | Free. |
| Session active (fast user switching) | `NSWorkspace.sessionDidResignActiveNotification`; `kCGSSessionOnConsoleKey`. | Free. |
| Lid | `AppleClamshellState` on IOPMrootDomain. | Free. |
| Screensaver | Distributed notifications `com.apple.screensaver.didstart/didstop` [unconfirmed]. | Free. |

Policy ideas these enable: user present (HID idle < 60 s) means the system will not idle-sleep anyway, so the engine can relax to slow polling; display asleep or locked + agent working is the only state where the assertion changes the outcome; lid closed on battery = nothing to do, notify instead.

---

## 8. Efficiency: cheapest design that reacts in about 5 s

Measured unit costs [proven-here]: sysctl census 0.2 ms; rusage per pid ~3 microseconds; fd/socket list per process ~20-50 microseconds; `stat` ~1 microsecond; clamshell read 2.5 microseconds; `ps` spawn ~28 ms wall and about 30 ms CPU across two processes, plus a fork of a Swift app's address space.

Today: `ps` every 5 s = roughly 0.6 percent of one core on average and a process spawn every 5 s (each spawn also wakes `launchservicesd`/`syspolicyd`-style observers and defeats timer coalescing).

Design:
1. **Event sources carry the fast path** (zero cost when idle):
   - process source per tracked agent: exit, fork, exec;
   - `EVFILT_VNODE` on active transcript/WAL files; FSEvents only for discovery of new session files;
   - NSWorkspace launch/terminate for the Electron/GUI agents;
   - power source, sleep/wake, display sleep, lock, thermal, Low Power Mode notifications.
2. **One adaptive timer carries the rest**:
   - *Discovery tick* (find new CLI agents): sysctl census every 5 s while no agent is known; 0.2 ms each. This is the only thing that needs polling, because unprivileged macOS has no global exec event.
   - *Activity tick* (only while at least one agent exists): every 2 s, `proc_pid_rusage` on each tracked subtree pid + `stat` of its tty; every 4-6 s, socket list. Total for 50 pids: about 0.2 ms.
   - *Idle backoff*: all agents quiet for N minutes and assertion released: stretch to 10-15 s, and let any event source (fork, transcript write, tty mtime change seen at next tick) snap it back to 2 s.
3. **Hysteresis in the verdict, not in the sampling**: hold the assertion for a grace period (for example 60-90 s) after the last positive signal; that also covers the "waiting on the model, zero CPU" gap. The assertion timeout key doubles as this grace period.

Timers and App Nap [primary: Apple Energy Efficiency Guide]: an app is an App Nap candidate when it "isn't the foreground app", "hasn't recently updated content in the visible portion of a window", "isn't audible", "hasn't taken any IOKit power management or NSProcessInfo assertions". Napped apps get "timer throttling", priority reduction and I/O throttling. An LSUIElement menu bar app with no visible window is a prime candidate **exactly when it holds no assertion**, that is, while it waits for an agent to start. Effects: a 5 s timer can stretch to tens of seconds [unconfirmed magnitude]. Mitigations:
- Kernel event sources (process, vnode, FSEvents, IOKit notifications) still fire while napped; they wake the app.
- Hold `ProcessInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason:)` for the app's lifetime, or only while agents exist. It disables App Nap and does not block sleep [primary, header]. Alternative: `defaults write <bundle id> NSAppSleepDisabled -bool YES` / `LSAppNapIsDisabled` in Info.plist [unconfirmed].
- Use `DispatchSourceTimer` with a leeway of 10-20 percent of the interval (for example 2 s with 400 ms leeway) so the kernel coalesces your wake with others. Never `.strict`.
- QoS: run the sampler on a `.utility` queue. `.background` can be starved and is clamped to E-cores with deferred timers and throttled I/O; under Low Power Mode and thermal pressure it can wait seconds. `.utility` is still E-core-preferred and energy-efficient. UI stays on main.
- Do not spawn subprocesses on the tick. Each spawn costs more than 100 sweeps of libproc.

Expected steady-state cost: under 0.02 percent of a core with agents present, effectively zero without (one 0.2 ms census per 5 s).

---

## 9. Surprises and traps

1. **`task_for_pid` is dead for this purpose.** Against a hardened-runtime target it needs the target to carry `get-task-allow`, or the caller to be root with SIP debugging off or hold `com.apple.system-task-ports` (Apple-private). Mach-based `task_info`, `thread_info`, reading another process's memory: all out. libproc is the replacement and needs none of that. [unconfirmed today; standard since 10.14/11]
2. **mach time units on Apple silicon** (section 1.2). Classic bug: CPU percent off by 41.67x. [proven-here]
3. **`ps` is setuid root; your app is not.** Anything `ps`/`top` show for root processes is not reachable through libproc. `KERN_PROC_ALL` still lists them with basic fields. [proven-here]
4. **FSEvents fires on close only** (section 3). [proven-here + primary]
5. **`ucomm` of Claude Code is a version string**; Bun/Node single-file binaries and symlinked installs make `comm` useless. Match on path. [proven-here]
6. **Electron splits work across processes.** Renderer had CPU but 0 sockets; the engine (`codex`) had the :443 socket and the transcript fds; network in general lives in a "Network Service" helper. Group by responsible pid or coalition, then sum. [proven-here]
7. **QoS CPU buckets are empty for CLIs.** [proven-here]
8. **`PreventSystemSleep` is silently downgraded on battery**, and the keys that would fix it are entitlement-gated in powerd, not in the kernel, so the call returns success and simply does nothing. Check `pmset -g log` for truth. [primary + log evidence]
9. **`NOTE_TRACK` is ENOTSUP on macOS** and NOTE_FORK carries no child pid. [primary; fork event proven-here]
10. **`KERN_PROCARGS2` omits environment variables of hardened-runtime processes** for other callers; argv remains. Do not design a signal around reading another process's env (for example `CLAUDECODE=1`) if the target may be hardened. Unhardened CLIs (node, bun) still expose env. [primary]
11. **`nstat_privcheck` is 0 on macOS** (1 on iOS): per-process byte counters are reachable unprivileged, but only through a private framework or the raw kernel control socket protocol, which changes between releases. [primary + sysctl proven-here]
12. **Sandbox would break most of this.** `proc_pidinfo` on other processes, `KERN_PROCARGS2` and IOKit rootDomain access are filtered by the App Sandbox MAC hooks. The app must stay non-sandboxed (so no Mac App Store). Hardened runtime alone blocks none of the calls in this note: all probes here are plain user-space syscalls with no special entitlement. [unconfirmed for a notarized build, since probes here were ad-hoc signed; no entitlement is involved in any of the calls, so no difference is expected]
13. **macOS 15 / 26 changes**: I found no kernel change that restricts same-user libproc calls; everything above ran on macOS 26.7.1. macOS 14+ added the "app would like to access data from other apps" TCC prompt for reads inside `~/Library/Containers/<other app>`; a sandboxed agent app that keeps transcripts there would trigger it. macOS 15 made the Screen Recording grant expire/re-prompt periodically, another reason to avoid window-title scraping. [unconfirmed, from release-era knowledge]
14. **`pmset -g assertionslog` never exits.** It hung my shell for 120 s. Never run it from code without a timeout. [proven-here]
15. **Wake-ups with the lid closed on battery are frequent** (291 maintenance dark wakes in the log, 45 s each). Agents advance a little in each. A transcript can therefore show activity "during sleep". Do not treat that as proof that the Mac stayed awake. [proven-here from log]

---

## 10. Recommended low-level stack

- **Census:** `sysctl KERN_PROC_ALL` every 5 s (2 s while agents exist). Identity = (pid, start time). Match agents by `proc_pidpath` / `KERN_PROCARGS2`.
- **Grouping:** ppid tree for CLIs; responsible pid (fallback: coalition id, fallback: bundle path prefix) for app helpers.
- **Work signals per group, 2 s tick:** deltas of `ri_user_time + ri_system_time` (with timebase), `ri_energy_nj`, `ri_instructions`, `ri_logical_writes`, `ri_interrupt_wkups`; `stat` mtime of the agent's tty; foreground-job test (`pgid == tpgid`) and `pbi_status` to discount stopped/background jobs.
- **Waiting-on-network signal, 4-6 s tick:** ESTABLISHED TCP :443 socket present in the group (`PROC_PIDFDSOCKETINFO`). Optional later: NetworkStatistics byte deltas behind a feature flag.
- **Events:** `DispatchSource` process sources (exit/fork/exec) per agent root; `EVFILT_VNODE` on transcript and `-wal` files found by FSEvents (creation) or by `PROC_PIDLISTFDS`; NSWorkspace app launch/terminate.
- **Power out:** one `PreventUserIdleSystemSleep` assertion with a re-armed timeout (dead-man switch) and a Details string; optionally `PreventSystemSleep` on AC for lid-closed dark-wake operation, with the UI honest that battery + lid closed always sleeps.
- **Power in:** `IORegisterForSystemPower` (reset deltas on wake, last-look on WillSleep), `IOPSNotificationCreateRunLoopSource`, clamshell properties, display sleep / lock notifications, HID idle, thermal and Low Power Mode notifications.
- **Runtime hygiene:** `.utility` queue, coalescing timer with leeway, `beginActivity(.userInitiatedAllowingIdleSystemSleep)` against App Nap, no subprocess spawns, no private API in the default path except the undeclared `responsibility_get_pid_responsible_for_pid` and coalition flavor (both with public fallbacks).
