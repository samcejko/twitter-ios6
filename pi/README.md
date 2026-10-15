# Chirpie helper (Raspberry Pi)

The small service the iOS 6 app (Chirpie) talks to. X's web API needs a login session, a CSRF token and a rotating
`x-client-transaction-id` header that is computed by obfuscated JavaScript - none of which iOS 6 can do. This helper
does it with `twikit` and hands the app tiny JSON.

**Multi-user and stateless.** It stores nothing. Each request carries the user's own X cookies (`auth_token` + `ct0`)
in headers; the helper signs that one request with them and forgets them. Many people can share one helper, each with
their own account. No password ever reaches the server. Images and videos stream from Twitter's CDN straight to the
device (the app does its own TLS); only `/proxy` moves bytes through the helper (fallback away from home).

> **Account note.** This signs in to X the unofficial-web-API way (through `twikit`), not the paid API. Automated
> access can get an account rate-limited or locked. Everyone shares this helper's IP for the API calls, so keep it to
> people you trust and expect occasional rate-limiting if a lot of accounts hammer it.

## Run

```sh
docker compose up -d --build
curl http://<pi>:8740/health          # {"ok": true}
```

Nothing to configure - each user logs in from the app. To share it, point your nginx/cloudflared at
`http://127.0.0.1:8740` and hand out the address. There is no server key: the helper does nothing without a user's
own cookies, so the address is all anyone needs.

## How a user logs in (what the app's login screen asks for)

In a desktop browser logged in to **x.com**: open DevTools → Application (or Storage) → Cookies → `https://x.com`,
and copy the values of **`auth_token`** and **`ct0`**. Paste them into Chirpie's login screen (the Cookies tab).
They stay on the device; the app sends them with each request. (On an iOS device a cookie-viewer tweak / bookmarklet
can read them too.) To sign out, the app clears them; nothing lives on the server.

The login screen also has a **Password** tab (username + password, behind a consent note): the password is sent over
HTTPS, used once here via `POST /login` to fetch the cookies, and never stored or logged - only the cookies come
back to the device. Cookies are the safer option; the password one is just for convenience.

## Keep it working

`twifork` (a maintained fork of twikit that imports as `twikit`) is the piece that ages - upstream `twikit` on PyPI
is currently broken against X's 2026 webpack bundle ("Couldn't get KEY_BYTE indices"), so this uses twifork. When X
changes something again:

```sh
pip install -U twifork    # or: docker compose build --no-cache && docker compose up -d
```

## Endpoints

Cookies travel in headers (`X-Chirpie-Auth` = auth_token, `X-Chirpie-CT0` = ct0), never stored.

| path | returns |
|------|---------|
| `/health` | `{ok}` - service up (no cookies needed) |
| `/me` | the signed-in account for the given cookies |
| `/timeline?feed=foryou\|following&cursor=` | a page of the home timeline |
| `/user?name=` · `/tweets?name=&id=&kind=&cursor=` | a profile · their tweets |
| `/tweet?id=&cursor=` | a tweet with its thread |
| `/search?q=&kind=top\|latest\|people&cursor=` · `/trends` | search · trends |
| `/bookmarks` · `/notifications?kind=all\|mentions` | your bookmarks · notifications |
| `/followers?name=&id=` · `/following?…` | people lists |
| `/action?do=like\|unlike\|retweet\|unretweet\|bookmark\|unbookmark\|delete\|follow\|unfollow&id=` | a write action |
| `POST /post` `{text,replyTo,quoteUrl,imageB64,imageType}` | a tweet / reply / quote |
| `GET /dm/list` · `GET /dm/history?name=&id=` · `POST /dm/send` `{name\|id,text}` | direct messages |
| `/proxy?u=` | media bytes (twimg.com hosts only), Range supported (no cookies) |
