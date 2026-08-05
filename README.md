# PostgreSQL Schema Tracker

This project snapshots all DDL in a configured PostgreSQL schema, commits changes to Git, and pushes them to a remote repository. It does not dump table rows, object ownership, or privileges.

Each configured database produces one file:

```text
schemas/<database>/<schema>.sql
```

The extraction is equivalent to:

```bash
pg_dump --schema-only --no-owner --no-privileges \
  --restrict-key=7cL3mQ9vN2xR8kT5pW4dF6hJ1sB0yGzA \
  --host=<host> --port=<port> --username=<user> \
  --schema=<schema> --dbname=<database>
```

## Configuration

Copy the examples and set the connection details:

```bash
cp sp-tracker.conf.example sp-tracker.conf
cp secret.pgpass.example secret.pgpass
```

Set `SCHEMA=bcadb` to track the complete `bcadb` schema. `DATABASE` accepts a comma-separated list, and each database is dumped to its own directory. Set `PG_DUMP` when the executable is not named `pg_dump` or is not on the default `PATH`. The stable restriction key prevents unchanged dumps from receiving randomized `pg_dump` metadata and producing false Git changes.

`secret.pgpass` contains only the database password on its first non-empty line. Both local configuration files are excluded from Git.

## Run on Linux

```bash
chmod +x bin/*.sh
./bin/setup.sh
./bin/sync.sh
```

`sync.sh` dumps the configured schema atomically, commits the snapshot when it changes, and pushes the commit to the configured branch and remote. Remove obsolete snapshot files manually after removing a database from `DATABASE` or changing `SCHEMA`.

To install the configured daily cron job:

```bash
./bin/register-task.sh
```

## Run with Docker

Build and run from the repository root after creating `sp-tracker.conf` and `secret.pgpass`. This example assumes the configured Git remote uses SSH:

```bash
docker build -t bca-sp-tracker .
docker run --rm \
  -e GIT_AUTHOR_NAME="$(git config user.name)" \
  -e GIT_AUTHOR_EMAIL="$(git config user.email)" \
  -e GIT_COMMITTER_NAME="$(git config user.name)" \
  -e GIT_COMMITTER_EMAIL="$(git config user.email)" \
  -v "${HOME}/.ssh:/root/.ssh:ro" \
  -v "$(pwd):/app" \
  bca-sp-tracker
```