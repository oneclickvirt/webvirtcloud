#!/usr/bin/env bash
set -e

.venv/bin/python3 manage.py migrate
.venv/bin/python3 manage.py first_init_data

exit 0
