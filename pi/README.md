# Chirpie helper (Raspberry Pi)

The small service the iOS 6 app (Chirpie) talks to. It signs in once with **your** X / Twitter account, keeps the
session, and hands the app tiny JSON. Images and videos stream from Twitter's own CDN (`pbs.twimg.com`,
`video.twimg.com`); only `/proxy` moves the bytes through the Pi (the fallback away from home). Read-only: the app
only reads what your account can see - it never posts, likes, follows or sends anything.

> **Account note.** This signs in to X the way a browser does (the unofficial web API, through `twikit`), not the
> paid API. Use an account you are willing to risk - automated access can get an account rate-limited or locked. Put
> the credentials only here, on your own machine.

## Run

```sh
# put your account in a .env file next to docker-compose.yml (it never leaves the Pi):
#   CHIRPIE_X_USERNAME=yourhandle
#   CHIRPIE_X_EMAIL=you@example.com
#   CHIRPIE_X_PASSWORD=your-password
#   CHIRPIE_X_TOTP=ABCD...        # only if the account has two-factor auth (the secret, not a code)
docker compose up -d --build
curl http://<pi>:8740/health        # {"ok": true, "account": "yourhandle"}
```

The session cookies are cached in `./data/cookies.json`, so the helper logs in once and reuses it after that.

## Keep it working

X changes often; `twikit` is the maintained piece. When something stops working:

```sh
pip install -U twikit    # or: docker compose build --no-cache && docker compose up -d
```

## Exposing beyond the LAN

Set `CHIRPIE_KEY` in `docker-compose.yml`; the app must then send `?k=<key>` (or the `X-Chirpie-Key` header). Point
your existing nginx / cloudflared at `http://127.0.0.1:8740`. In the app: Settings → the server address (and key).

## Endpoints

| path | returns |
|------|---------|
| `/health` | `{ok, account}` - the signed-in `@handle` |
| `/timeline?feed=foryou\|following&cursor=` | a page of the home timeline |
| `/user?name=<handle>` | `{user}` - name, bio, avatar, banner, counts |
| `/tweets?name=&id=&kind=tweets\|replies\|media\|likes&cursor=` | a person's tweets |
| `/tweet?id=&cursor=` | `{tweet, ancestors, replies, cursor, hasMore}` |
| `/search?q=&kind=top\|latest\|people&cursor=` | tweets, or people |
| `/trends` | `{items:[{name, query, volume, context}]}` |
| `/proxy?u=` | the media bytes (twimg.com hosts only), Range supported |

Each list returns `{tweets:[…], bottom:"<cursor>", hasMore:bool}` (people search adds `users`). The app passes
`bottom` back as `cursor` for the next page.
