#!/usr/bin/env python3
"""Chirpie helper - the small, multi-user service that runs on your own server (a Raspberry Pi is perfect).

The iOS 6 app cannot sign requests to X / Twitter (X's web API needs a login session, a rotating
`x-client-transaction-id` header computed by obfuscated JavaScript, and a CSRF token), so the app does not talk to
X directly. This helper does the signing with `twikit` and turns X's answers into the tiny JSON the app parses.

It is **stateless about who you are**: each request carries the user's own X cookies (auth_token + ct0) in headers;
the helper signs that one request with them and keeps nothing. Many people can share one helper, each with their own
account - no password ever reaches the server, nothing is stored per user. Pictures and videos stream from Twitter's
CDN straight to the device (the app does its own TLS); only /proxy moves bytes through the helper (fallback / away
from home).

The maintained piece is `twikit`. When X changes something and a call stops working, update it on the server - the
app does not need rebuilding:  pip install -U twikit  (or: docker compose up -d --build)

The user gets their cookies once, in a desktop browser logged in to x.com: DevTools -> Application -> Cookies ->
https://x.com -> copy the values of `auth_token` and `ct0`, and paste them into the app's login screen.

Settings (docker-compose.yml / env):
    CHIRPIE_KEY    (optional) require ?k=<key> (or X-Chirpie-Key) on every call when exposed beyond the LAN
    CHIRPIE_PORT   (optional) the port, default 8740

Cookies travel in the request headers (per user, never stored):
    X-Chirpie-Auth : the auth_token cookie
    X-Chirpie-CT0  : the ct0 cookie

Endpoints (all JSON unless noted):
    GET /health                              {ok}  - the service is up (no cookies needed)
    GET /me                                  {user} - the signed-in account for the given cookies
    GET /timeline?feed=foryou|following&cursor=
    GET /user?name=<handle>                  {user}
    GET /tweets?name=&id=&kind=tweets|replies|media|likes&cursor=
    GET /tweet?id=&cursor=                   {tweet, ancestors, replies, cursor, hasMore}
    GET /search?q=&kind=top|latest|people&cursor=
    GET /trends
    GET /bookmarks?cursor=
    GET /notifications?kind=all|mentions&cursor=
    GET /followers?name=&id=&cursor=   GET /following?...
    GET /action?do=like|unlike|retweet|unretweet|bookmark|unbookmark|delete|follow|unfollow&id=
    POST /post        {text, replyTo, quoteUrl, imageB64, imageType}
    GET /dm/list      GET /dm/history?name=&id=&cursor=      POST /dm/send {name|id, text}
    GET /proxy?u=<pbs/video.twimg.com url>   the media bytes, Range supported (no cookies needed)
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
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
      "Chrome/124.0.0.0 Safari/537.36")
TWIMG_RE = re.compile(r"(^|\.)twimg\.com$", re.I)

# --- one asyncio loop in a background thread; HTTP handler threads submit coroutines to it -----------------

_LOOP = asyncio.new_event_loop()


def _loop_thread():
    asyncio.set_event_loop(_LOOP)
    _LOOP.run_forever()


threading.Thread(target=_loop_thread, daemon=True).start()


def run(coro, timeout=40):
    return asyncio.run_coroutine_threadsafe(coro, _LOOP).result(timeout=timeout)


# A small cache of twikit clients keyed by auth_token, so a busy user reuses one (all touched only on the loop).
_CLIENTS = {}   # auth_token -> [client, last_used]


async def _client_for(auth, ct0):
    if not auth:
        raise PermissionError("login required")
    ent = _CLIENTS.get(auth)
    if ent is None:
        ent = [Client("en-US"), 0.0]
        _CLIENTS[auth] = ent
        if len(_CLIENTS) > 60:   # evict the least-recently-used
            oldest = min(_CLIENTS, key=lambda k: _CLIENTS[k][1])
            if oldest != auth:
                _CLIENTS.pop(oldest, None)
    client = ent[0]
    client.set_cookies({"auth_token": auth, "ct0": ct0 or ""}, clear_cookies=True)
    ent[1] = time.time()
    return client


async def _myid(client):
    uid = getattr(client, "_ch_uid", None)
    if uid is None:
        u = await client.user()
        uid = str(getattr(u, "id", "") or "")
        client._ch_uid = uid
    return uid


async def call(auth, ct0, fn, *args):
    """Resolve the user's client from their cookies, then run one endpoint coroutine with it."""
    client = await _client_for(auth, ct0)
    return await fn(client, *args)


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
    return re.sub(r"_normal(\.[a-zA-Z]+)$", r"_400x400\1", url or "")


def _expand_user_url(u):
    url = getattr(u, "url", "") or ""
    ent = getattr(u, "entities", None)
    if isinstance(ent, dict):
        for e in (ent.get("url", {}) or {}).get("urls", []):
            if e.get("url") == url and e.get("expanded_url"):
                return e["expanded_url"]
    return url


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
        "isFollowing": bool(getattr(u, "is_following", None) if getattr(u, "is_following", None) is not None else getattr(u, "following", False)),
        "followsYou": bool(getattr(u, "followed_by", False)),
    }


def _pick_video(media):
    streams = getattr(media, "streams", None) or []
    best = None
    for s in streams:
        ct = (getattr(s, "content_type", "") or "").lower()
        url = getattr(s, "url", "") or ""
        if "mp4" not in ct and "mp4" not in url:
            continue
        br = _int(getattr(s, "bitrate", 0))
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
    text = getattr(tweet, "full_text", None) or getattr(tweet, "text", "") or ""
    urls = getattr(tweet, "urls", None) or []
    for e in urls:
        tco = e.get("url") if isinstance(e, dict) else getattr(e, "url", None)
        disp = (e.get("display_url") if isinstance(e, dict) else getattr(e, "display_url", None)) or ""
        exp = (e.get("expanded_url") if isinstance(e, dict) else getattr(e, "expanded_url", None)) or tco
        if not tco:
            continue
        if re.search(r"(^|//)(twitter\.com|x\.com)/.+/(status|photo|video)/", exp or "") or "pic.twitter.com" in disp or "pic.x.com" in disp:
            text = text.replace(tco, "")
        else:
            text = text.replace(tco, exp)
    return text.strip()


def tweet_json(tweet, myid="", depth=0):
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
        "favorited": bool(getattr(tweet, "favorited", False)),
        "retweeted": bool(getattr(tweet, "retweeted", False)),
        "bookmarked": bool(getattr(tweet, "bookmarked", False) or getattr(tweet, "is_bookmarked", False)),
        "media": [media_json(m) for m in media],
    }
    if retweeter is not None:
        out["retweetedBy"] = {"name": getattr(retweeter, "name", "") or "", "handle": getattr(retweeter, "screen_name", "") or ""}
    if quoted is not None and depth < 1:
        out["quoted"] = tweet_json(quoted, myid, depth + 1)
    return out


def page_json(result, myid=""):
    tweets = [tweet_json(t, myid) for t in (result or [])]
    tweets = [t for t in tweets if t and t["id"]]
    cursor = getattr(result, "next_cursor", "") or ""
    return {"tweets": tweets, "bottom": cursor, "hasMore": bool(cursor and tweets)}


def users_page(result):
    users = [user_json(u) for u in (result or [])]
    users = [u for u in users if u and u["handle"]]
    cursor = getattr(result, "next_cursor", "") or ""
    return {"users": users, "bottom": cursor, "hasMore": bool(cursor and users)}


def _notification_json(n, myid=""):
    icon = getattr(n, "icon", None)
    icon_id = icon.get("id", "") if isinstance(icon, dict) else (getattr(icon, "id", "") or (str(icon) if icon else ""))
    msg = getattr(n, "message", None)
    text = msg if isinstance(msg, str) else (getattr(msg, "text", "") if msg is not None else "")
    users = getattr(n, "from_users", None) or ([getattr(n, "from_user")] if getattr(n, "from_user", None) else [])
    tj = None
    nt = getattr(n, "tweet", None)
    if nt is not None:
        try:
            tj = tweet_json(nt, myid)
        except Exception:
            tj = None
    ts = getattr(n, "timestamp_ms", None)
    return {"id": str(getattr(n, "id", "") or ""), "icon": icon_id or "", "text": text or "",
            "time": int(int(ts) / 1000) if ts else 0,
            "users": [u for u in (user_json(x) for x in users) if u], "tweet": tj}


def _message_json(m, myid):
    sender = str(getattr(m, "sender_id", "") or "")
    t = getattr(m, "time", 0)
    return {"id": str(getattr(m, "id", "") or ""), "text": getattr(m, "text", "") or "",
            "time": _int(t) // 1000 if str(t).isdigit() else 0, "senderId": sender, "fromMe": sender == myid}


# --- endpoint coroutines (each gets the signed-in user's client) ------------------------------------------

async def me(client):
    u = await client.user()
    if hasattr(u, "id"):
        client._ch_uid = str(getattr(u, "id", "") or "")
    return {"user": user_json(u)}


async def timeline(client, feed, cursor):
    if feed == "following":
        result = await (client.get_latest_timeline(count=20) if not cursor else client.get_latest_timeline(count=20, cursor=cursor))
    else:
        result = await (client.get_timeline(count=20) if not cursor else client.get_timeline(count=20, cursor=cursor))
    myid = await _myid(client)
    return page_json(result, myid)


async def user(client, name):
    return {"user": user_json(await client.get_user_by_screen_name(name))}


async def user_tweets(client, name, uid, kind, cursor):
    if not uid:
        u = await client.get_user_by_screen_name(name)
        uid = str(getattr(u, "id", "") or "")
    product = {"tweets": "Tweets", "replies": "Replies", "media": "Media", "likes": "Likes"}.get(kind, "Tweets")
    result = await (client.get_user_tweets(uid, product, count=20) if not cursor else client.get_user_tweets(uid, product, count=20, cursor=cursor))
    return page_json(result, await _myid(client))


async def _parent_id(tweet):
    pid = getattr(tweet, "in_reply_to", None)
    return str(pid) if pid and str(pid).isdigit() else ""


async def thread(client, tid, cursor):
    myid = await _myid(client)
    focal = await client.get_tweet_by_id(tid)
    focal_json = tweet_json(focal, myid)
    ancestors = []
    chain = getattr(focal, "reply_to", None)
    if isinstance(chain, (list, tuple)) and chain:
        ancestors = [a for a in (tweet_json(t, myid) for t in chain) if a and a["id"]]
        ancestors.reverse()
    else:
        cur = focal
        for _ in range(4):
            pid = await _parent_id(cur)
            if not pid:
                break
            try:
                p = await client.get_tweet_by_id(pid)
            except Exception:
                break
            aj = tweet_json(p, myid)
            if aj and aj["id"]:
                ancestors.insert(0, aj)
            cur = p
    replies_result = getattr(focal, "replies", None)
    if cursor and hasattr(focal, "get_replies"):
        try:
            replies_result = await focal.get_replies(cursor=cursor)
        except TypeError:
            replies_result = getattr(focal, "replies", None)
    replies = [r for r in (tweet_json(t, myid) for t in (replies_result or [])) if r and r["id"] and r["id"] != focal_json["id"]]
    next_cursor = getattr(replies_result, "next_cursor", "") or ""
    return {"tweet": focal_json, "ancestors": ancestors, "replies": replies, "cursor": next_cursor, "hasMore": bool(next_cursor and replies)}


async def search(client, query, kind, cursor):
    if kind == "people":
        result = await (client.search_user(query, count=20) if not cursor else client.search_user(query, count=20, cursor=cursor))
        up = users_page(result)
        return {"tweets": [], "users": up["users"], "bottom": up["bottom"], "hasMore": up["hasMore"]}
    product = "Latest" if kind == "latest" else "Top"
    result = await (client.search_tweet(query, product, count=20) if not cursor else client.search_tweet(query, product, count=20, cursor=cursor))
    out = page_json(result, await _myid(client))
    out["users"] = []
    return out


async def trends(client):
    try:
        items = await client.get_trends("trending")
    except Exception as e:
        sys.stderr.write("chirpie: trends failed: %s\n" % e)
        return {"items": []}
    out = []
    for t in items or []:
        name = getattr(t, "name", "") or ""
        if name:
            out.append({"name": name, "query": name, "volume": _int(getattr(t, "tweet_volume", 0) or 0),
                        "context": getattr(t, "domain_context", "") or getattr(t, "category", "") or ""})
    return {"items": out}


async def bookmarks(client, cursor):
    result = await (client.get_bookmarks(count=20) if not cursor else client.get_bookmarks(count=20, cursor=cursor))
    return page_json(result, await _myid(client))


async def notifications(client, kind, cursor):
    t = {"mentions": "Mentions", "verified": "Verified"}.get(kind, "All")
    result = await (client.get_notifications(t, count=40) if not cursor else client.get_notifications(t, count=40, cursor=cursor))
    myid = await _myid(client)
    items = [_notification_json(n, myid) for n in (result or [])]
    c = getattr(result, "next_cursor", "") or ""
    return {"items": items, "bottom": c, "hasMore": bool(c and items)}


async def followers(client, uid, name, which, cursor):
    if not uid:
        u = await client.get_user_by_screen_name(name)
        uid = str(getattr(u, "id", "") or "")
    fn = client.get_user_following if which == "following" else client.get_user_followers
    result = await (fn(uid, count=20) if not cursor else fn(uid, count=20, cursor=cursor))
    return users_page(result)


async def do_action(client, action, obj_id):
    a = (action or "").lower()
    fns = {"like": client.favorite_tweet, "unlike": client.unfavorite_tweet, "retweet": client.retweet,
           "unretweet": client.delete_retweet, "bookmark": client.bookmark_tweet, "unbookmark": client.delete_bookmark,
           "delete": client.delete_tweet, "follow": client.follow_user, "unfollow": client.unfollow_user}
    fn = fns.get(a)
    if not fn:
        raise ValueError("unknown action")
    await fn(obj_id)
    return {"ok": True, "action": a, "id": str(obj_id)}


async def post_tweet(client, text, reply_to, quote_url, image_bytes, media_type):
    media_ids = []
    if image_bytes:
        import tempfile
        suffix = ".png" if (media_type or "").endswith("png") else ".jpg"
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as f:
            f.write(image_bytes)
            tmp = f.name
        try:
            media_ids.append(await client.upload_media(tmp, wait_for_completion=True))
        finally:
            try:
                os.remove(tmp)
            except OSError:
                pass
    kwargs = {}
    if media_ids:
        kwargs["media_ids"] = media_ids
    if reply_to:
        kwargs["reply_to"] = reply_to
    if quote_url:
        kwargs["attachment_url"] = quote_url
    t = await client.create_tweet(text=text or "", **kwargs)
    return {"ok": True, "id": str(getattr(t, "id", "") or "")}


async def dm_history(client, uid, name, cursor):
    if not uid:
        u = await client.get_user_by_screen_name(name)
        uid = str(getattr(u, "id", "") or "")
    myid = await _myid(client)
    result = await (client.get_dm_history(uid) if not cursor else client.get_dm_history(uid, max_id=cursor))
    msgs = [_message_json(m, myid) for m in (result or [])]
    c = getattr(result, "next_cursor", "") or (msgs[-1]["id"] if msgs else "")
    return {"items": msgs, "uid": uid, "cursor": c, "hasMore": bool(getattr(result, "next_cursor", ""))}


async def dm_send(client, uid, name, text):
    if not uid:
        u = await client.get_user_by_screen_name(name)
        uid = str(getattr(u, "id", "") or "")
    myid = await _myid(client)
    m = await client.send_dm(uid, text)
    return {"ok": True, "message": _message_json(m, myid), "uid": uid}


async def dm_list(client):
    for meth in ("get_dm_inbox", "get_inbox", "get_dm_conversations"):
        fn = getattr(client, meth, None)
        if fn is None:
            continue
        try:
            result = await fn()
        except Exception as e:
            sys.stderr.write("chirpie: %s failed: %s\n" % (meth, e))
            continue
        convos = []
        for c in result or []:
            u = getattr(c, "user", None) or getattr(c, "participant", None)
            last = getattr(c, "last_message", None) or getattr(c, "message", None)
            convos.append({"user": user_json(u), "last": getattr(last, "text", "") if last else "",
                           "time": _int(getattr(last, "time", 0)) // 1000 if last and str(getattr(last, "time", "")).isdigit() else 0})
        return {"items": [c for c in convos if c["user"]], "supported": True}
    return {"items": [], "supported": False}


# --- HTTP -------------------------------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "chirpie/2.0"

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

    def _cookies(self, q):
        auth = self.headers.get("X-Chirpie-Auth", "") or q.get("a", [""])[0]
        ct0 = self.headers.get("X-Chirpie-CT0", "") or q.get("c", [""])[0]
        return auth, ct0

    def log_message(self, fmt, *args):
        sys.stderr.write("chirpie %s - %s\n" % (self.address_string(), fmt % args))

    def do_HEAD(self):
        self.do_GET()

    def _run(self, fn, *args):
        """Run an endpoint with the request's cookies; 401 when they are missing."""
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        auth, ct0 = self._cookies(q)
        if not auth:
            return self._send_json({"error": "login required", "needsLogin": True}, 401)
        try:
            return self._send_json(run(call(auth, ct0, fn, *args), timeout=45))
        except PermissionError:
            return self._send_json({"error": "login required", "needsLogin": True}, 401)
        except Exception as e:
            sys.stderr.write("chirpie error: %s\n" % e)
            return self._send_json({"error": "upstream failed", "detail": str(e)[:200]}, 502)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        q = urllib.parse.parse_qs(parsed.query)
        one = lambda n, d="": q.get(n, [d])[0]
        if path == "/health":
            return self._send_json({"ok": True})
        if not self._authorized(q):
            return self._send_json({"error": "unauthorized"}, 401)
        if path == "/proxy":
            return self._proxy(one("u") or one("url"))
        routes = {
            "/me": (me,),
            "/timeline": (timeline, one("feed", "foryou"), one("cursor")),
            "/user": (user, one("name")),
            "/tweets": (user_tweets, one("name"), one("id"), one("kind", "tweets"), one("cursor")),
            "/tweet": (thread, one("id"), one("cursor")),
            "/search": (search, one("q"), one("kind", "top"), one("cursor")),
            "/trends": (trends,),
            "/bookmarks": (bookmarks, one("cursor")),
            "/notifications": (notifications, one("kind", "all"), one("cursor")),
            "/followers": (followers, one("id"), one("name"), "followers", one("cursor")),
            "/following": (followers, one("id"), one("name"), "following", one("cursor")),
            "/action": (do_action, one("do"), one("id")),
            "/dm/list": (dm_list,),
            "/dm/history": (dm_history, one("id"), one("name"), one("cursor")),
        }
        r = routes.get(path)
        if r:
            return self._run(*r)
        return self._send_json({"error": "not found"}, 404)

    def do_POST(self):
        import base64
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        q = urllib.parse.parse_qs(parsed.query)
        if not self._authorized(q):
            return self._send_json({"error": "unauthorized"}, 401)
        auth, ct0 = self._cookies(q)
        if not auth:
            return self._send_json({"error": "login required", "needsLogin": True}, 401)
        length = _int(self.headers.get("Content-Length", 0))
        try:
            body = json.loads(self.rfile.read(length).decode("utf-8")) if length else {}
        except ValueError:
            return self._send_json({"error": "bad json"}, 400)
        try:
            if path == "/post":
                image = base64.b64decode(body["imageB64"]) if body.get("imageB64") else None
                return self._send_json(run(call(auth, ct0, post_tweet, body.get("text", ""), body.get("replyTo", ""),
                                                body.get("quoteUrl", ""), image, body.get("imageType", "")), timeout=120))
            if path == "/dm/send":
                return self._send_json(run(call(auth, ct0, dm_send, body.get("id", ""), body.get("name", ""), body.get("text", ""))))
        except PermissionError:
            return self._send_json({"error": "login required", "needsLogin": True}, 401)
        except Exception as e:
            sys.stderr.write("chirpie error on POST %s: %s\n" % (path, e))
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
    sys.stderr.write("chirpie helper listening on :%d (key %s, multi-user cookie mode)\n" % (PORT, "set" if KEY else "off"))
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
