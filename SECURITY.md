# Security

Report a security problem to hi@caffeinagent.com. Do not open a public issue for it.

- Say what you found, how to see it, and which version of Agent Caffeine you used.
- Only the latest release gets fixes.

The sensitive part is the helper (`CaffeinagentHelper`). It runs as root, sets the `SleepDisabled` setting of macOS and keeps one wake time in the schedule of macOS. It takes calls only from a copy of the app that the same Developer ID signed (`Caffeinagent/Power/SleepFlagHelperProtocol.swift`). A way around that check is the most important thing to report.
