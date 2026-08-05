FROM ubuntu:latest

RUN apt-get update && apt-get install -y \
    postgresql-client \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN git config --system --add safe.directory /app

WORKDIR /app

COPY sp-tracker.conf ./
COPY bin/ ./bin/

RUN chmod +x ./bin/*.sh

CMD ["./bin/sync.sh"]