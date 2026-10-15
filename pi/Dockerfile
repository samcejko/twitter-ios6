# Chirpie helper for the Raspberry Pi. twikit speaks X's web API; everything else is Python stdlib.
FROM python:3.12-slim

RUN pip install --no-cache-dir -U twikit

COPY chirpie_server.py /app/chirpie_server.py
WORKDIR /app

ENV CHIRPIE_PORT=8740
ENV CHIRPIE_COOKIES=/data/cookies.json
EXPOSE 8740

# twikit is the part that ages; rebuild (or `pip install -U twikit` in the container) when X changes.
CMD ["python", "/app/chirpie_server.py"]
