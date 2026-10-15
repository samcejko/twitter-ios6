# Chirpie helper for the Raspberry Pi. It speaks X's web API through `twifork`, a maintained fork of twikit that
# keeps the x-client-transaction-id / ondemand.s.js parsing current (upstream `twikit` 2.3.3 on PyPI is broken against
# X's 2026 webpack bundle: "Couldn't get KEY_BYTE indices"). twifork imports as `twikit`, so the code is unchanged.
FROM python:3.12-slim

RUN pip install --no-cache-dir -U twifork

COPY chirpie_server.py /app/chirpie_server.py
WORKDIR /app

ENV CHIRPIE_PORT=8740
EXPOSE 8740

# twikit is the part that ages; rebuild (or `pip install -U twikit` in the container) when X changes.
CMD ["python", "/app/chirpie_server.py"]
