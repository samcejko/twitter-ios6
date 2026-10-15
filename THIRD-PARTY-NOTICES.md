# Third-party notices

Chirpie bundles or depends on the following third-party components.

## mbedTLS

The app's TLS layer (so iOS 6 can reach modern HTTPS servers) is built on mbedTLS.
<https://github.com/Mbed-TLS/mbedtls> — Apache-2.0 (the library is fetched by CI; its LICENSE ships inside the app).

## CA certificates

The trust store is Mozilla's CA bundle as distributed by the curl project (<https://curl.se/ca/cacert.pem>),
fetched at build time and shipped inside the app as `cacert.pem`. Mozilla Public License 2.0.

## twikit (server-side only, not shipped in the app)

The `chirpie` helper uses twikit to speak X's web API. <https://github.com/d60/twikit> — MIT.
It runs on your own server and is never part of the iOS app.

## Trademarks

X and Twitter and their logos are trademarks of X Corp. Chirpie is an unofficial, independent client and is not
affiliated with, endorsed by or associated with X Corp. The app's icon is an original design.
