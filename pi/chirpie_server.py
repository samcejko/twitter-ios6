#!/usr/bin/env python3
"""Chirpie helper - the small service that runs on your own server (a Raspberry Pi is perfect).

The iOS 6 app cannot sign requests to X / Twitter, so it does not talk to X directly. This helper signs in once
with YOUR X account (the credentials come from the environment, below), keeps the session cookies, and turns X's
answers into the tiny JSON the app parses. Images and videos stream from Twitter's own CDN (pbs/video.twimg.com):
the app fetches them through its own TLS layer, or - away from home - through the /proxy here.

Read-only: the app only reads what your account can see. It never posts, likes, follows or sends anything.

The maintained piece is `twikit` (the library that speaks X's private web API). When X changes something and a call
stops working, update it on the server - the app does not need rebuilding:

    pip install -U twikit && docker compose up -d --build

Sign-in (set these in docker-compose.yml, env or a .env file next to it):
    CHIRPIE_X_USERNAME   your @handle (without the @)
    CHIRPIE_X_EMAIL      the account's email (X sometimes asks for it during login)
    CHIRPIE_X_PASSWORD   the account's password
    CHIRPIE_X_TOTP       (optional) the TOTP secret if the account has two-factor authentication
    CHIRPIE_KEY          (optional) require ?k=<key> (or X-Chirpie-Key) on every call when exposed beyond the LAN
    CHIRPIE_PORT         (optional) the port, default 8740
    CHIRPIE_COOKIES      (optional) where the session is cached, default /data/cookies.json

Endpoints (all JSON unless noted):
    GET /health                              {ok, account}
    GET /timeline?feed=foryou|following&cursor=
    GET /user?name=<handle>                  {user}
    GET /tweets?name=&id=&kind=tweets|replies|media|likes&cursor=
    GET /tweet?id=&cursor=                   {tweet, ancestors, replies, cursor, hasMore}
    GET /search?q=&kind=top|latest|people&cursor=
    GET /suggest?q=
    GET /trends
    GET /proxy?u=<pbs/video.twimg.com url>   the media bytes, Range supported
"""
import asyncio
import json
import os
import re
import sys
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

try:
    from twikit import Client
except ImportError:
    sys.exit("chirpie: twikit is not installed (pip install twikit)")

KEY = os.environ.get("CHIRPIE_KEY", "")
PORT = int(os.environ.get("CHIRPIE_PORT", "8740"))
COOKIES = os.environ.get("CHIRPIE_COOKIES", "/data/cookies.json")
USERNAME = os.environ.get("CHIRPIE_X_USERNAME", "")
EMAIL = os.environ.get("CHIRPIE_X_EMAIL", "")
PASSWORD = os.environ.get("CHIRPIE_X_PASSWORD", "")
TOTP = os.environ.get("CHIRPIE_X_TOTP", "")
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
      "Chrome/124.0.0.0 Safari/537.36")
TWIMG_RE = re.compile(r"(^|\.)twimg\.com$", re.I)

# --- one asyncio loop in a background thread; HTTP handler threads submit coroutines to it -----------------

_LOOP = asyncio.new_event_loop()
_CLIENT = Client("en-US")
_READY = {"account": "", "error": "", "logged_in": False}
_LOGIN_LOCK = threading.Lock()


def _loop_thread():
    asyncio.set_event_loop(_LOOP)
    _LOOP.run_forever()


threading.Thread(target=_loop_thread, daemon=True).start()


def run(coro, timeout=40):
    """Run a coroutine on the background loop from a handler thread and wait for the result."""
    return asyncio.run_coroutine_threadsafe(coro, _LOOP).result(timeout=timeout)


async def _ensure_login():
    if _READY["logged_in"]:
        return
    with _LOGIN_LOCK:
        if _READY["logged_in"]:
            return
        try:
            if os.path.exists(COOKIES):
                _CLIENT.load_cookies(COOKIES)
                me = await _CLIENT.user()
                _READY.update(account=getattr(me, "screen_name", "") or "", logged_in=True, error="")
                return
        except Exception as e:
            sys.stderr.write("chirpie: cached session invalid (%s); logging in again\n" % e)
        if not USERNAME or not PASSWORD:
            _READY["error"] = "no credentials set (CHIRPIE_X_USERNAME / CHIRPIE_X_PASSWORD)"
            raise RuntimeError(_READY["error"])
        kwargs = dict(auth_info_1=USERNAME, auth_info_2=EMAIL or USERNAME, password=PASSWORD)
        if TOTP:
            kwargs["totp_secret"] = TOTP
        await _CLIENT.login(**kwargs)
        try:
            os.makedirs(os.path.dirname(COOKIES) or ".", exist_ok=True)
            _CLIENT.save_cookies(COOKIES)
        except Exception as e:
            sys.stderr.write("chirpie: could not save cookies: %s\n" % e)
        me = await _CLIENT.user()
        _READY.update(account=getattr(me, "screen_name", "") or "", logged_in=True, error="")


# --- turning twikit objects into the app's JSON -----------------------------------------------------------

def _int(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return 0


def _ts(tweet):
    dt = getattr(tweet, "created_at_datetime", None)
    if dt is not None:
        try:
            return int(dt.timestamp())
        except Exception:
            pass
    s = getattr(tweet, "created_at", None)
    if s:
        try:
            import email.utils
            return int(email.utils.mktime_tz(email.utils.parsedate_tz(s)))
        except Exception:
            return 0
    return 0


def _user_ts(user):
    s = getattr(user, "created_at", None)
    if not s:
        return 0
    try:
        import email.utils
        return int(email.utils.mktime_tz(email.utils.parsedate_tz(s)))
    except Exception:
        return 0


def _avatar(url):
    # the _normal (48px) avatar -> the larger _400x400 when the pattern matches
    u = url or ""
    return re.sub(r"_normal(\.[a-zA-Z]+)$", r"_400x400\1", u)


def user_json(u):
    if u is None:
        return None
    return {
        "id": str(getattr(u, "id", "") or ""),
        "handle": getattr(u, "screen_name", "") or "",
        "name": getattr(u, "name", "") or "",
        "bio": getattr(u, "description", "") or "",
        "avatar": _avatar(getattr(u, "profile_image_url", None) or getattr(u, "profile_image_url_https", None)),
        "banner": getattr(u, "profile_banner_url", "") or "",
        "verified": bool(getattr(u, "verified", False) or getattr(u, "is_blue_verified", False)),
        "protected": bool(getattr(u, "protected", False)),
        "followers": _int(getattr(u, "followers_count", 0)),
        "following": _int(getattr(u, "following_count", 0) or getattr(u, "friends_count", 0)),
        "tweets": _int(getattr(u, "statuses_count", 0)),
        "likes": _int(getattr(u, "favourites_count", 0)),
        "location": getattr(u, "location", "") or "",
        "url": _expand_user_url(u),
        "created": _user_ts(u),
        "pinnedId": (getattr(u, "pinned_tweet_ids", None) or [""])[0] if getattr(u, "pinned_tweet_ids", None) else "",
    }


def _expand_user_url(u):
    url = getattr(u, "url", "") or ""
    for e in (getattr(u, "entities", {}) or {}).get("url", {}).get("urls", []) if isinstance(getattr(u, "entities", None), dict) else []:
        if e.get("url") == url and e.get("expanded_url"):
            return e["expanded_url"]
    return url


def _pick_video(media):
    """A playable MP4 for iOS 6 (H.264): the highest-bitrate mp4 at or under ~720p worth of bitrate."""
    streams = getattr(media, "streams", None) or []
    best = None
    for s in streams:
        ct = (getattr(s, "content_type", "") or "").lower()
        url = getattr(s, "url", "") or ""
        if "mp4" not in ct and not url.endswith(".mp4") and "mp4" not in url:
            continue
        br = _int(getattr(s, "bitrate", 0))
        # prefer the best bitrate up to ~2.5 Mbps (about 720p); fall back to the smallest if all are higher
        if best is None:
            best = (br, url)
        elif br <= 2500000 and br > best[0]:
            best = (br, url)
        elif best[0] > 2500000 and br < best[0]:
            best = (br, url)
    return best[1] if best else ""


def media_json(m):
    t = (getattr(m, "type", "") or "photo").lower()
    out = {"type": "photo", "w": _int(getattr(m, "width", 0)), "h": _int(getattr(m, "height", 0)),
           "alt": getattr(m, "alt_text", "") or getattr(m, "ext_alt_text", "") or ""}
    sizes = getattr(m, "sizes", None) or {}
    if isinstance(sizes, dict):
        lg = sizes.get("large") or sizes.get("medium") or {}
        if isinstance(lg, dict) and lg.get("w"):
            out["w"], out["h"] = _int(lg.get("w")), _int(lg.get("h"))
    if t in ("video", "animated_gif"):
        out["type"] = "video" if t == "video" else "gif"
        out["url"] = _pick_video(m)
        out["preview"] = getattr(m, "media_url", "") or getattr(m, "thumbnail_url", "") or ""
    else:
        out["type"] = "photo"
        url = getattr(m, "media_url", "") or getattr(m, "media_url_https", "") or ""
        out["url"] = (url + "?name=large") if url and "?" not in url else url
        out["preview"] = url
    return out


def _expand_text(tweet):
    """The tweet's full text with t.co links replaced by their real address and the trailing media / quote link
    removed (X appends one t.co at the end that points at the photo or the quoted tweet)."""
    text = getattr(tweet, "full_text", None) or getattr(tweet, "text", "") or ""
    urls = getattr(tweet, "urls", None) or []
    trailing = []
    for e in urls:
        tco = e.get("url") if isinstance(e, dict) else getattr(e, "url", None)
        disp = (e.get("display_url") if isinstance(e, dict) else getattr(e, "display_url", None)) or ""
        exp = (e.get("expanded_url") if isinstance(e, dict) else getattr(e, "expanded_url", None)) or tco
        if not tco:
            continue
        # a link to the quoted tweet or to a pic is shown as media/quote, not as text
        if re.search(r"(^|//)(twitter\.com|x\.com)/.+/(status|photo|video)/", exp or "") or "pic.twitter.com" in disp or "pic.x.com" in disp:
            trailing.append(tco)
            text = text.replace(tco, "")
        else:
            text = text.replace(tco, exp)
    return text.strip()


def tweet_json(tweet, depth=0):
    if tweet is None:
        return None
    rt = getattr(tweet, "retweeted_tweet", None)
    retweeter = None
    if rt is not None:
        retweeter = getattr(tweet, "user", None)
        tweet = rt
    media = getattr(tweet, "media", None) or []
    quoted = getattr(tweet, "quote", None)
    out = {
        "id": str(getattr(tweet, "id", "") or ""),
        "author": user_json(getattr(tweet, "user", None)),
        "text": _expand_text(tweet),
        "created": _ts(tweet),
        "lang": getattr(tweet, "lang", "") or "",
        "replies": _int(getattr(tweet, "reply_count", 0)),
        "retweets": _int(getattr(tweet, "retweet_count", 0)),
        "likes": _int(getattr(tweet, "favorite_count", 0)),
        "quotes": _int(getattr(tweet, "quote_count", 0)),
        "views": _int(getattr(tweet, "view_count", 0) or 0),
        "sensitive": bool(getattr(tweet, "possibly_sensitive", False)),
        "conversationId": str(getattr(tweet, "conversation_id", "") or ""),
        "replyToId": str(getattr(tweet, "in_reply_to", "") or ""),
        "replyToHandle": getattr(tweet, "in_reply_to_screen_name", "") or "",
        "media": [media_json(m) for m in media],
    }
    if retweeter is not None:
        out["retweetedBy"] = {"name": getattr(retweeter, "name", "") or "", "handle": getattr(retweeter, "screen_name", "") or ""}
    if quoted is not None and depth < 1:
        out["quoted"] = tweet_json(quoted, depth + 1)
    return out


def page_json(result):
    tweets = [tweet_json(t) for t in (result or [])]
    tweets = [t for t in tweets if t and t["id"]]
    cursor = getattr(result, "next_cursor", "") or ""
    return {"tweets": tweets, "bottom": cursor, "hasMore": bool(cursor and tweets)}


# --- endpoint coroutines ----------------------------------------------------------------------------------

async def timeline(feed, cursor):
    await _ensure_login()
    if feed == "following":
        result = await _CLIENT.get_latest_timeline(count=20) if not cursor else await _CLIENT.get_latest_timeline(count=20, cursor=cursor)
    else:
        result = await _CLIENT.get_timeline(count=20) if not cursor else await _CLIENT.get_timeline(count=20, cursor=cursor)
    return page_json(result)


async def user(name):
    await _ensure_login()
    u = await _CLIENT.get_user_by_screen_name(name)
    return {"user": user_json(u)}


async def user_tweets(name, uid, kind, cursor):
    await _ensure_login()
    if not uid:
        u = await _CLIENT.get_user_by_screen_name(name)
        uid = str(getattr(u, "id", "") or "")
    kinds = {"tweets": "Tweets", "replies": "Replies", "media": "Media", "likes": "Likes"}
    product = kinds.get(kind, "Tweets")
    result = await _CLIENT.get_user_tweets(uid, product, count=20) if not cursor else await _CLIENT.get_user_tweets(uid, product, count=20, cursor=cursor)
    return page_json(result)


async def _parent_id(tweet):
    pid = getattr(tweet, "in_reply_to", None)
    # some twikit versions expose the parent tweet id here; others only the user id. accept a numeric string.
    return str(pid) if pid and str(pid).isdigit() else ""


async def thread(tid, cursor):
    await _ensure_login()
    focal = await _CLIENT.get_tweet_by_id(tid)
    focal_json = tweet_json(focal)
    # ancestors: prefer twikit's own reply_to chain, else walk parents by id (capped)
    ancestors = []
    chain = getattr(focal, "reply_to", None)
    if isinstance(chain, (list, tuple)) and chain:
        ancestors = [tweet_json(t) for t in chain]
        ancestors = [a for a in ancestors if a and a["id"]]
        ancestors.reverse()
    else:
        cur = focal
        for _ in range(4):
            pid = await _parent_id(cur)
            if not pid:
                break
            try:
                p = await _CLIENT.get_tweet_by_id(pid)
            except Exception:
                break
            aj = tweet_json(p)
            if aj and aj["id"]:
                ancestors.insert(0, aj)
            cur = p
    replies_result = getattr(focal, "replies", None)
    if cursor and hasattr(focal, "get_replies"):
        try:
            replies_result = await focal.get_replies(cursor=cursor)
        except TypeError:
            replies_result = getattr(focal, "replies", None)
    replies = [tweet_json(t) for t in (replies_result or [])]
    replies = [r for r in replies if r and r["id"] and r["id"] != focal_json["id"]]
    next_cursor = getattr(replies_result, "next_cursor", "") or ""
    return {"tweet": focal_json, "ancestors": ancestors, "replies": replies, "cursor": next_cursor, "hasMore": bool(next_cursor and replies)}


async def search(query, kind, cursor):
    await _ensure_login()
    if kind == "people":
        result = await _CLIENT.search_user(query, count=20) if not cursor else await _CLIENT.search_user(query, count=20, cursor=cursor)
        users = [user_json(u) for u in (result or [])]
        users = [u for u in users if u and u["handle"]]
        c = getattr(result, "next_cursor", "") or ""
        return {"tweets": [], "users": users, "bottom": c, "hasMore": bool(c and users)}
    product = "Latest" if kind == "latest" else "Top"
    result = await _CLIENT.search_tweet(query, product, count=20) if not cursor else await _CLIENT.search_tweet(query, product, count=20, cursor=cursor)
    out = page_json(result)
    out["users"] = []
    return out


async def suggest(query):
    # X's typeahead; twikit does not wrap it, so call the endpoint directly through the signed client when it can,
    # otherwise return nothing (the app falls back to recent searches)
    return {"items": []}


async def trends():
    await _ensure_login()
    try:
        items = await _CLIENT.get_trends("trending")
    except Exception as e:
        sys.stderr.write("chirpie: trends failed: %s\n" % e)
        return {"items": []}
    out = []
    for t in items or []:
        name = getattr(t, "name", "") or ""
        if not name:
            continue
        out.append({"name": name, "query": name, "volume": _int(getattr(t, "tweet_volume", 0) or 0),
                    "context": getattr(t, "domain_context", "") or getattr(t, "category", "") or ""})
    return {"items": out}


# --- HTTP -------------------------------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "chirpie/1.0"

    def _send_json(self, obj, status=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _authorized(self, q):
        if not KEY:
            return True
        return q.get("k", [""])[0] == KEY or self.headers.get("X-Chirpie-Key", "") == KEY

    def log_message(self, fmt, *args):
        sys.stderr.write("chirpie %s - %s\n" % (self.address_string(), fmt % args))

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        q = urllib.parse.parse_qs(parsed.query)
        one = lambda name, default="": q.get(name, [default])[0]
        if path == "/health":
            try:
                run(_ensure_login(), timeout=60)
            except Exception as e:
                return self._send_json({"ok": False, "error": _READY["error"] or str(e)[:200]})
            return self._send_json({"ok": True, "account": _READY["account"]})
        if not self._authorized(q):
            return self._send_json({"error": "unauthorized"}, 401)
        try:
            if path == "/timeline":
                return self._send_json(run(timeline(one("feed", "foryou"), one("cursor"))))
            if path == "/user":
                return self._send_json(run(user(one("name"))))
            if path == "/tweets":
                return self._send_json(run(user_tweets(one("name"), one("id"), one("kind", "tweets"), one("cursor"))))
            if path == "/tweet":
                return self._send_json(run(thread(one("id"), one("cursor"))))
            if path == "/search":
                return self._send_json(run(search(one("q"), one("kind", "top"), one("cursor"))))
            if path == "/suggest":
                return self._send_json(run(suggest(one("q"))))
            if path == "/trends":
                return self._send_json(run(trends()))
            if path == "/proxy":
                return self._proxy(one("u") or one("url"))
        except Exception as e:
            sys.stderr.write("chirpie error on %s: %s\n" % (path, e))
            return self._send_json({"error": "upstream failed", "detail": str(e)[:200]}, 502)
        return self._send_json({"error": "not found"}, 404)

    def _proxy(self, u):
        if not u or not re.match(r"^https://", u):
            return self._send_json({"error": "bad url"}, 400)
        host = urllib.parse.urlparse(u).hostname or ""
        if not TWIMG_RE.search(host):
            return self._send_json({"error": "host not allowed"}, 403)
        req = urllib.request.Request(u, headers={"User-Agent": UA, "Referer": "https://twitter.com/"})
        rng = self.headers.get("Range")
        if rng:
            req.add_header("Range", rng)
        try:
            up = urllib.request.urlopen(req, timeout=25)
        except Exception as e:
            return self._send_json({"error": "fetch failed", "detail": str(e)[:200]}, 502)
        self.send_response(up.status)
        for h in ("Content-Type", "Content-Length", "Content-Range", "Accept-Ranges"):
            v = up.headers.get(h)
            if v:
                self.send_header(h, v)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        if self.command == "HEAD":
            up.close()
            return
        try:
            while True:
                chunk = up.read(65536)
                if not chunk:
                    break
                self.wfile.write(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            up.close()


def main():
    sys.stderr.write("chirpie helper listening on :%d (key %s, account %s)\n"
                     % (PORT, "set" if KEY else "off", USERNAME or "unset"))
    try:
        run(_ensure_login(), timeout=90)
        sys.stderr.write("chirpie: signed in as @%s\n" % _READY["account"])
    except Exception as e:
        sys.stderr.write("chirpie: not signed in yet (%s); /health will keep trying\n" % e)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
