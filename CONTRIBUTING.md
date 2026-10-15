# Contributing

## Building without a Mac

Every push builds on GitHub Actions (`.github/workflows/build.yml`): Theos, the iOS 9.3 SDK, a Linux clang
toolchain and Mbed TLS are fetched there. The result is an IPA and a DEB in the `Chirpie-packages` artifact. A
syntax-check step lists every compile error at once; the full log is in `build-log`.

`tools/gh-push.ps1 -Message "..."` pushes through the GitHub API (no git),
`tools/gh-build.ps1 -Download -HeadSha <sha>` waits and downloads,
`. .\tools\ipad.ps1; Install-IPadPackage -IpaPath ...` installs over SSH, `Enable-ChirpieDebug` turns on the
`chirpie:` debug commands, `Get-ChirpieLog` reads the log, `Get-IPadScreen -OutFile x.png` grabs the screen.
`tools/local.json` (ignored) holds the repo, token and device address. The bundle, executable, bundle id, the
`[Chirpie]` log prefix and the `chirpie:` / `chirp:` URL schemes all use the name Chirpie.

## The helper

`pi/` is the server-side helper (Python + twikit, Docker). It is the part that ages with Twitter; keep it current
with `docker compose build --no-cache`. The app speaks a tiny JSON contract to it (see `pi/README.md`); keep that
contract stable, or bump both sides together.

## Ground rules

- iOS 6.0 deployment target, armv7 only. Anything newer than iOS 6 is a compile error (the pragma in `CHCommon.h`).
- ARC; UI in code, no storyboards. All networking through the `CHTLSSocket`/`CHHTTP` stack.
- Read-only in the app: it never posts, likes, retweets, follows or sends messages. Sign-in lives only in the
  helper (the user's own X account); credentials never touch the app or the repository.
- The app ships in English and Czech, both complete. Text shown to the user goes through `L()` (the English text is
  the key; `Resources/en.lproj` exists so iOS lists English); `Resources/cs.lproj` has the Czech.
  `tools/check-strings.ps1` lists gaps.
- No secrets in the repository; the server key is entered on the device and kept in the keychain.

## In the pull request

Say what you tested on a real device (model, iOS version) and attach a screenshot when the UI changed.
