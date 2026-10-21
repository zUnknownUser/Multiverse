#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
script="${1:-test:all}"
case "$script" in
  test:all|test:e2e|check) ;;
  *) echo "Usage: bash scripts/with-test-db.sh [test:all|test:e2e|check]" >&2; exit 2 ;;
esac
if ! docker info >/dev/null 2>&1; then
  echo "Docker is required. Start Docker and retry; no existing database will be used." >&2
  exit 1
fi

container="multiverse-test-$$-$RANDOM"
test_pid=''
cleanup() {
  if [[ -n "$test_pid" ]] && kill -0 "$test_pid" 2>/dev/null; then
    kill -TERM "$test_pid" 2>/dev/null || true
    wait "$test_pid" || true
  fi
  if ! docker rm --force "$container" >/dev/null 2>&1; then
    echo "Could not remove test container $container; check Docker before retrying." >&2
    return 1
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Loopback-only, random port, disposable credentials and no persistent volume.
docker run --detach --rm --name "$container" \
  --label com.multiverse.test-database=true \
  --publish 127.0.0.1::5432 \
  --env POSTGRES_USER=multiverse_test \
  --env POSTGRES_PASSWORD=multiverse_test_only \
  --env POSTGRES_DB=multiverse_test \
  postgres:18-alpine >/dev/null

ready=false
for ((attempt = 0; attempt < 60; attempt++)); do
  if docker exec "$container" pg_isready -h 127.0.0.1 -U multiverse_test -d multiverse_test >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  echo "PostgreSQL did not become ready within 60 seconds." >&2
  exit 1
fi

port="$(docker inspect --format '{{(index (index .NetworkSettings.Ports "5432/tcp") 0).HostPort}}' "$container")"
export TEST_DATABASE_URL="postgresql://multiverse_test:multiverse_test_only@127.0.0.1:$port/multiverse_test"
echo "Running $script against disposable PostgreSQL 18 on localhost:$port."
npm run "$script" &
test_pid=$!
wait "$test_pid"
