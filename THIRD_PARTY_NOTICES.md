# Third-party notices

Agent Caffeine for Mac carries the components below, each under its own
license. The full license texts are in `Resources/Licenses/` beside this file,
and in `Contents/Resources/Licenses/` inside the app, next to a copy of this
file.

## Components

| Component | Version               | License | In the app as                           | Source                                                   |
| --------- | --------------------- | ------- | --------------------------------------- | -------------------------------------------------------- |
| Sparkle   | 2.10.0 or a later 2.x | MIT     | `Contents/Frameworks/Sparkle.framework` | <https://github.com/sparkle-project/Sparkle/tree/2.10.0> |

Sparkle comes in as a Swift package: `project.yml` asks for 2.10.0 up to the
next major, and the version a build resolved is in its `Package.resolved`.

License texts, by file name in `Resources/Licenses/`:

- `Sparkle.txt`: the MIT license of Sparkle with its copyright lines, followed
  by the licenses of the code Sparkle itself includes (bsdiff, sais-lite,
  ed25519 and SUSignatureVerifier).
