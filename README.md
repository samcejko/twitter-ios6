# Chirpie - Twitter on iOS 6

An unofficial client for X / Twitter on jailbroken iOS 6.x (iPad 2 / iPhone 4S era) and, as a second build of the
same sources, for 64-bit devices with iOS 14–17 (iPhone X and newer: rootless jailbreaks and TrollStore), in English
and Czech. The classic blue-bird look, native to the iOS 6 Twitter era. Five tabs — Home, Explore, Notifications,
Messages, Me — with your home timeline (For You and Following), tweet threads, profiles, search (Top, Latest,
People), trends, photos and videos; and the full set of actions: reply, repost, like, bookmark, quote, follow,
compose (with a photo) and direct messages.

Everything runs through **your own X account** on your own server. Chirpie is not affiliated with, endorsed by or
associated with X Corp or Twitter.

## How it works (and why it needs a helper)

X's web API needs a login session, a CSRF token and a rotating `x-client-transaction-id` header computed by
obfuscated JavaScript - none of which iOS 6 can produce - and logged-out access gives almost nothing any more. So
Chirpie does not talk to X directly. A tiny helper (the `chirpie` service) runs on a server (a Raspberry Pi is
perfect) and does the signing with `twikit`.

The helper is **multi-user and stateless**: it stores nothing. Each person signs in with their **own** X cookies
(`auth_token` + `ct0`), which stay on their device and travel with each request; the helper signs that one request
and forgets them. One helper can serve many people, each with their own account - no password ever reaches the
server. Pictures and videos stream straight from Twitter's CDN to the device through Chirpie's own TLS layer (iOS 6
cannot talk to modern servers otherwise); away from home, the helper can also stream the bytes.

When X changes something, you update `twikit` on the server - the app does not need rebuilding.

See [`pi/README.md`](pi/README.md) to run the helper (Docker). Then in the app: Settings → set the server address
(e.g. `https://chirpie.samcejko.eu`), then **Log in** and paste your `auth_token` and `ct0` from a browser signed in
to x.com (Settings → Account, or the prompt that appears).

> **Account note.** This signs in the unofficial-web-API way (through `twikit`), not the paid API. Automated access
> can get an account rate-limited or locked, and everyone on one helper shares its IP, so keep a shared helper to
> people you trust. No password reaches the server; cookies live only on each device.

## Using it

- **Home** - the timeline, with a For You / Following switch; the compose button is top-right. Pull to refresh.
- **Explore** - search (Top, Latest, People) and the current trends; your recent searches stay on the device.
- **Notifications** - likes, reposts, follows, mentions and replies (All / Mentions).
- **Messages** - your conversations; start one from a profile or the compose button.
- **Me** - your own profile, with Settings and your Bookmarks in the bar.
- Each tweet has reply, repost, like, bookmark and a … menu (quote, copy link, share, open in browser, delete your
  own). Tap a tweet for its thread, an avatar or name for the profile, a photo or video to open it full screen.
- Links, `@mentions` and `#hashtags`: a twitter.com / x.com link opens inside Chirpie, a YouTube / Twitch / Kick /
  TikTok link in Tubie / Twitcher / Kicker / TikTak when that app is installed, anything else in Safari or Surfari.
- Link scheme: `chirpie:open?url=<a tweet or profile link>`, `chirpie:tweet/<id>`, `chirpie:user/<handle>`,
  `chirpie:search?q=<words>`, `chirpie:tag/<hashtag>`, and `chirpie:server?url=&key=` to set the helper.

## Installing on the device

The easy way: add the repository `http://repo.samcejko.eu/` in Cydia (Sources → Edit → Add), Sileo, Zebra or
Installer and install Chirpie from there; updates then come through the package manager. The app is free; if it is
useful to you, you can support the development at [ko-fi.com/samcejko](https://ko-fi.com/samcejko).

By hand: the IPA installs with `ipainstaller -f Chirpie-<version>.ipa` (AppSync Unified), or the DEB with `dpkg -i`
then `su mobile -c uicache`. Do not keep both installed at once.

On iOS 14–17 (64-bit): with a rootless jailbreak add the same repository in Sileo or Zebra, or install the
`iphoneos-arm64` `.deb` with `dpkg -i` (it goes into `/var/jb/Applications`); without a jailbreak open
`Chirpie-<version>-arm64.ipa` in [TrollStore](https://github.com/opa334/TrollStore). The same app, the same iOS 6
look. CI builds both from one source tree (`make package THEOS_PACKAGE_SCHEME=rootless` for arm64, the iOS 16.5 SDK,
deployment target 14.0); the differences live in `src/Util/CHModern.m` and `tools/modern_bundle.py`.

## Project layout

```
pi/           the helper that runs on your server (Python + twikit, Docker)
src/Twitter   the data layer: models, and the client that talks to the helper
src/Net       TLS socket, HTTP client, image loader, the media proxy that feeds the video player
src/UI        timeline, tweet threads, profiles, search, the media viewer, settings, the iOS 6 theme
src/Util      formatting, settings, the iOS 7+ bridge that keeps the iOS 6 look
tools         push/build/release/device scripts, the icon, the asset generator
vendor        mbedTLS configuration and glue (the library is fetched by CI)
```

## Privacy

Your recent searches live on the device; bookmarks are your account's own X bookmarks. The app talks only to your
own helper and to Twitter's media CDN. No account credentials live in the app, no telemetry - the sign-in stays on
your server.

## License

MIT, see [`LICENSE`](LICENSE). Third-party notices in [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).
