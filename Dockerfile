# syntax=docker/dockerfile:1

FROM ghcr.io/linuxserver/baseimage-alpine:3.21 AS buildbase

# set version label
ARG BUILD_DATE
ARG VERSION
ARG YOUR_SPOTIFY_VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thespad"

RUN \
  echo "**** install buildstage packages ****" && \
  apk -U --update --no-cache add --virtual=build-dependencies \
    build-base \
    cmake \
    npm \
    python3-dev \
    yarn && \
  echo "*** install your_spotify ***" && \
  if [ -z ${YOUR_SPOTIFY_VERSION+x} ]; then \
    YOUR_SPOTIFY_VERSION=$(curl -sX GET "https://api.github.com/repos/Yooooomi/your_spotify/releases/latest" \
    | awk '/tag_name/{print $4;exit}' FS='[""]'); \
  fi && \
  curl -o \
    /tmp/your_spotify.tar.gz -L \
    "https://github.com/Yooooomi/your_spotify/archive/${YOUR_SPOTIFY_VERSION}.tar.gz" && \
  mkdir -p /app/www && \
  tar xzf \
    /tmp/your_spotify.tar.gz -C \
    /app/www/ --strip-components=1

FROM buildbase AS buildclient

RUN \
  echo "*** install your_spotify client ***" && \
  cd /app/www && \
  rm -rf /app/www/apps/server && \
  yarn --frozen-lockfile && \
  cd /app/www/apps/client && \
  yarn build && \
  rm -rf /app/www/node_modules && \
  yarn cache clean

FROM buildbase AS buildserver

RUN \
  echo "*** install your_spotify server ***" && \
  cd /app/www && \
  rm -rf /app/www/apps/client && \
  yarn --frozen-lockfile && \
  cd /app/www/apps/server && \
  yarn build && \
  rm -rf /app/www/node_modules && \
  yarn cache clean

FROM ghcr.io/linuxserver/baseimage-alpine-nginx:3.21

ARG BUILD_DATE
ARG VERSION
ARG YOUR_SPOTIFY_VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thespad"

ENV HOME=/app

COPY --from=buildclient /app/www/apps/client/build/ /app/www/apps/client/build/
COPY --from=buildbase /app/www/package.json /app/www/package.json
COPY --from=buildbase /app/www/yarn.lock /app/www/yarn.lock
COPY --from=buildserver /app/www/apps/server/lib/ /app/www/apps/server/lib/
COPY --from=buildserver /app/www/apps/server/package.json /app/www/apps/server/package.json

RUN \
  echo "**** install build packages ****" && \
  apk -U --update --no-cache add --virtual=build-dependencies \
    build-base \
    cmake \
    python3-dev && \
  echo "**** install runtime packages ****" && \
  apk add -U --update --no-cache \
    nodejs \
    npm \
    yarn && \
  echo "**** install your_spotify ****" && \
  cd /app/www/apps/server && \
  yarn --production --frozen-lockfile && \
  yarn cache clean && \
  npm install -g serve && \
  printf "Linuxserver.io version: ${VERSION}\nBuild-date: ${BUILD_DATE}" > /build_version && \
  echo "**** cleanup ****" && \
  apk del --purge \
    build-dependencies && \
  rm -rf \
    /tmp/* \
    $HOME/.cache \
    $HOME/.npm

COPY /root /

EXPOSE 80 443
