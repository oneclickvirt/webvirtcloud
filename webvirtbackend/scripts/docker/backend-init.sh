#!/usr/bin/env bash
set -e

docker compose exec backend python3 manage.py migrate
docker compose exec backend python3 manage.py first_init_data

exit 0
