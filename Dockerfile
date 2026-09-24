# syntax=docker/dockerfile:1.7@sha256:a57df69d0ea827fb7266491f2813635de6f17269be881f696fbfdf2d83dda33e
ARG FLUTTER_IMAGE=ghcr.io/cirruslabs/flutter:3.41.1@sha256:a2b70117a92ec3799128099d8849783877b5d8f2ed6ee323c4e01f18c7084aee
FROM --platform=$BUILDPLATFORM ${FLUTTER_IMAGE} AS build
ARG API_URL=http://localhost:8081
ARG APP_ENV=local
ARG LOCAL_AUTH_ENABLED=false
ARG SOURCE_REVISION=uncommitted
LABEL org.opencontainers.image.revision="$SOURCE_REVISION" \
      org.crystalweb.public-base-url="$API_URL" \
      org.crystalweb.app-env="$APP_ENV"
WORKDIR /src/frontend
COPY pubspec.yaml pubspec.lock ./
COPY third_party/pdfx/ ./third_party/pdfx/
RUN flutter pub get
COPY . ./
RUN test -n "$API_URL" \
 && flutter build web --release --base-href=/ \
      --dart-define="APP_ENV=$APP_ENV" \
      --dart-define="API_URL=$API_URL" \
      --dart-define="LOCAL_AUTH_ENABLED=$LOCAL_AUTH_ENABLED"

FROM nginxinc/nginx-unprivileged:1.27-alpine@sha256:65e3e85dbaed8ba248841d9d58a899b6197106c23cb0ff1a132b7bfe0547e4c0
ARG SOURCE_REVISION=uncommitted
ARG API_URL=http://localhost:8081
ARG APP_ENV=local
LABEL org.opencontainers.image.revision="$SOURCE_REVISION" \
      org.crystalweb.api-url="$API_URL" \
      org.crystalweb.app-env="$APP_ENV"
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/frontend/build/web/ /usr/share/nginx/html/
EXPOSE 8080
