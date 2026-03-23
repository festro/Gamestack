# ── Stage 1: build gst-interpipe from source ─────────────────────────────────
FROM ubuntu:24.04 AS interpipe-builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    autoconf \
    automake \
    libtool \
    pkg-config \
    gtk-doc-tools \
    make \
    gcc \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Clone and build gst-interpipe
RUN git clone --depth=1 https://github.com/RidgeRun/gst-interpipe.git /build/gst-interpipe

WORKDIR /build/gst-interpipe

RUN ./autogen.sh --libdir /usr/lib/$(uname -m)-linux-gnu/ \
    && make -j$(nproc) \
    && make install DESTDIR=/interpipe-out

# ── Stage 2: runtime image ────────────────────────────────────────────────────
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
    # runtime deps for gst-interpipe
    libgstreamer1.0-0 \
    libgstreamer-plugins-base1.0-0 \
    && pip3 install --break-system-packages websockets \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy built interpipe plugin from builder stage
COPY --from=interpipe-builder /interpipe-out/ /

# Refresh shared library cache
RUN ldconfig

WORKDIR /app

COPY sidecar/ ./sidecar/
COPY client/  ./client/

EXPOSE 8088 8089

CMD ["python3", "sidecar/sidecar.py"]
