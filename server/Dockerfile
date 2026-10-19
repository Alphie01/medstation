# MedStation API. Build from the repository root:
#   docker build -f server/Dockerfile -t medstation-api .
FROM dart:3.9 AS build
WORKDIR /src
# The root workspace also lists the Flutter app, which needs the Flutter SDK;
# the image only needs the shared core and the server.
COPY packages/medstation_core/pubspec.yaml packages/medstation_core/
COPY server/pubspec.yaml server/
RUN printf 'name: medstation_workspace\npublish_to: none\nenvironment:\n  sdk: ^3.9.0\nworkspace:\n  - packages/medstation_core\n  - server\n' > pubspec.yaml \
 && dart pub get
COPY packages/medstation_core packages/medstation_core
COPY server server
RUN dart pub get --offline \
 && mkdir -p /out/bin \
 && for t in server migrate create_user seed_dev ingest_titck ingest_announcements ingest_documents fetch_kubkt import_clinical; do \
      dart compile exe server/bin/$t.dart -o /out/bin/$t; \
    done

FROM debian:bookworm-slim
# poppler-utils: pdftotext for fetch_kubkt; ca-certificates: OpenAI/TİTCK over TLS.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates poppler-utils curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 medstation
WORKDIR /app
COPY --from=build /out/bin/ /app/bin/
COPY server/migrations /app/migrations
COPY server/config /app/config
ENV PATH="/app/bin:${PATH}" PORT=8787
USER medstation
EXPOSE 8787
HEALTHCHECK --interval=10s --timeout=3s --retries=5 CMD curl -fs http://localhost:8787/health || exit 1
CMD ["server"]
