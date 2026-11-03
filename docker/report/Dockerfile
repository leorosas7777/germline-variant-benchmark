FROM python:3.14.10-slim-trixie@sha256:930e1abba7c4e8f96ed93e8012c35d174d7732752731bbd5e8e757d7ec6f3966

LABEL org.opencontainers.image.title="germline-benchmark-report" \
      org.opencontainers.image.description="Per-stratum precision/recall table from hap.py output" \
      org.opencontainers.image.source="https://github.com/leorosas7777/germline-variant-benchmark" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="0.1.0"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

COPY --chmod=0755 happy_strat_table.py /usr/local/bin/happy_strat_table.py

RUN useradd --create-home --uid 10001 report
USER report
