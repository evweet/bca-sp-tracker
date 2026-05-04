FROM ubuntu:latest

RUN apt-get update && apt-get install -y \
    postgresql-client \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY sp-tracker.conf ./
COPY src/ ./src/

RUN chmod +x ./src/*.sh

CMD ["./src/sync.sh"]