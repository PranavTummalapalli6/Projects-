# Pinned to one Debian release so a rebuild next month is the same image as
# today's. Bump it on purpose (and re-run the tests), not by accident.
FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    # OpenCV's own guard against decompression bombs: a tiny file that
    # declares enormous dimensions is refused instead of allocating gigabytes.
    OPENCV_IO_MAX_IMAGE_PIXELS=50000000

# OpenCV needs these system libraries even in "headless" mode, for image
# decoding/codec backends that opencv-python-headless still links against.
# tzdata gives zoneinfo the IANA time-zone database: the weekly summary
# buckets sessions by the player's own time zone, and the slim image ships
# without it (every zone lookup would fail).
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

# Run as an unprivileged user: a bug in image decoding shouldn't be root.
RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY --chown=app:app app ./app

USER app

# Cloud Run tells the container which port to use through $PORT; locally it
# falls back to 8000 (what docker-compose.yml maps).
ENV PORT=8000
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import os, urllib.request; urllib.request.urlopen('http://localhost:%s/healthz' % os.environ.get('PORT', '8000'))" || exit 1

# `exec` so the server, not a shell, receives SIGTERM when Cloud Run stops the instance.
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT}"]
