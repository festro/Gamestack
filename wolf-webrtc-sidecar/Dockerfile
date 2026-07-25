# Media arrives from Wolf through shmsink sockets in /tmp/sockets (see
# apply-wolf-tap.sh), so no gst-interpipe build is needed — interpipe only
# links pipelines inside a single process and never worked across containers.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV GST_DEBUG=2
ENV PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-gi \
    python3-gi-cairo \
    gir1.2-gst-plugins-base-1.0 \
    gir1.2-gstreamer-1.0 \
    gir1.2-gst-plugins-bad-1.0 \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    gstreamer1.0-nice \
    gstreamer1.0-tools \
    gstreamer1.0-vaapi \
    libva-drm2 \
    libva2 \
    libgstreamer1.0-0 \
    libgstreamer-plugins-base1.0-0 \
    && pip3 install --break-system-packages 'websockets>=14,<16' 'docker>=7,<8' \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY sidecar/ ./sidecar/
COPY client/  ./client/

EXPOSE 8088 8089

CMD ["python3", "sidecar/sidecar.py"]
