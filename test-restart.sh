#!/bin/bash
set -o errexit
set -o nounset

IMG="$1"

DB_CONTAINER="redis"
DATA_CONTAINER="${DB_CONTAINER}-data"

function cleanup {
  echo "Cleaning up"
  docker rm -f "$DB_CONTAINER" "$DATA_CONTAINER" >/dev/null 2>&1 || true
}

function wait_for_db {
  for _ in $(seq 1 1000); do
    if docker exec -it "$DB_CONTAINER" redis-cli -a pass ping >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done

  echo "DB never came online"
  docker logs "$DB_CONTAINER"
  return 1
}

trap cleanup EXIT
cleanup

echo "Creating data container"
docker create --name "$DATA_CONTAINER" "$IMG"

echo "Starting DB"
docker run -it --rm \
  -e USERNAME=user -e PASSPHRASE=pass -e DATABASE=db \
  --volumes-from "$DATA_CONTAINER" \
  "$IMG" --initialize \
  >/dev/null 2>&1

docker run -d --name="$DB_CONTAINER" \
  -e EXPOSE_HOST=127.0.0.1 -e EXPOSE_PORT_27217=27217 \
  --volumes-from "$DATA_CONTAINER" \
  "$IMG"

echo "Waiting for DB to come online"
wait_for_db

echo "Verifying DB clean shutdown message isn't present"
docker logs "$DB_CONTAINER" 2>&1 | grep -vqi "redis is now ready to exit"

echo "Restarting DB container"
date
docker top "$DB_CONTAINER"
docker restart -t 10 "$DB_CONTAINER"

echo "Waiting for DB to come back online"
wait_for_db

echo "DB came back online; checking for clean shutdown and recovery"
date
docker logs "$DB_CONTAINER" 2>&1 | grep -qi "redis is now ready to exit"

echo "Attempting unclean shutdown"
docker kill -s KILL "$DB_CONTAINER"
docker start "$DB_CONTAINER"

echo "Waiting for DB to come back online"
wait_for_db

echo "Checking DB started 3 times"
n_starts="$(docker logs "$DB_CONTAINER" 2>&1 | grep -ic "ready to accept connections")"
[[ "$n_starts" -eq 3 ]]
