#!/usr/bin/env bash
set -euo pipefail

ERRORS=0

log_pass() { printf '\033[32m[PASS]\033[0m %s\n' "$*"; }
log_warn() { printf '\033[33m[WARN]\033[0m %s\n' "$*"; }
log_fail() {
    printf '\033[31m[FAIL]\033[0m %s\n' "$*"
    ERRORS=$((ERRORS + 1))
}

check_absent() {
    local description="$1"
    local pattern="$2"
    shift 2
    if rg -n "$pattern" "$@" >/tmp/webvirtcloud-ci-match.txt 2>/dev/null; then
        log_fail "$description"
        sed -n '1,20p' /tmp/webvirtcloud-ci-match.txt
    else
        log_pass "$description"
    fi
}

echo "=== Shell syntax ==="
for script in scripts/install_*.sh webvirtcloud/webvirtcloud.sh webvirtcompute/scripts/*.sh; do
    [ -f "$script" ] || continue
    bash -n "$script" && log_pass "$script syntax"
done

echo
echo "=== Security baseline ==="
check_absent "No Django hardcoded insecure secret" 'django-insecure-' webvirtbackend/webvirtcloud/settings
check_absent "No default DB/RabbitMQ/email passwords in env or compose files" '((PASSWORD|PASS)[[:space:]]*[:=][[:space:]]*(django|admin|root|password)([[:space:]]|$))|MARIADB_ALLOW_EMPTY_ROOT_PASSWORD' webvirtcloud/env.common webvirtcloud/docker-compose.yml webvirtbackend/docker-compose.yml
check_absent "No wildcard CORS response headers in Caddy" 'Access-Control-Allow-Origin\s+\*' webvirtcloud/Caddyfile.letsencrypt webvirtcloud/Caddyfile.noncert webvirtcloud/Caddyfile.selfsigned
check_absent "No wildcard Django host or CORS defaults" 'ALLOWED_HOSTS\s*=\s*\["\*"\]|CORS_ORIGIN_ALLOW_ALL\s*=\s*True' webvirtbackend/webvirtcloud/settings
check_absent "No static compute daemon token in templates" '^token = [0-9a-fA-F]{32,}$' webvirtcompute/conf/webvirtcompute.ini webvirtcompute/configs/webvirtcompute.ini
check_absent "No static compute token in initial fixtures" '"token"[[:space:]]*:[[:space:]]*"[0-9a-fA-F]{32,}"' webvirtbackend/compute/fixtures
check_absent "Port mapping sync does not shell out" 'subprocess|os\.system|shell=True|curl |dig ' webvirtbackend/virtance/port_mapping.py webvirtbackend/virtance/serializers.py
if rg -n --glob "*.py" '(^|[^[:alnum:]_])(eval|exec)\(|pickle\.loads?|yaml\.load\(' webvirtbackend webvirtcompute prometheus-libvirt-exporter >/tmp/webvirtcloud-ci-match.txt 2>/dev/null; then
    log_fail "No unsafe Python dynamic execution or deserialization"
    sed -n '1,20p' /tmp/webvirtcloud-ci-match.txt
else
    log_pass "No unsafe Python dynamic execution or deserialization"
fi

if rg -n "def is_expired" webvirtbackend/account/models.py >/dev/null &&
    rg -n "token\.is_expired\(\)" webvirtbackend/webvirtcloud/authentication.py >/dev/null; then
    log_pass "API token expiration is enforced"
else
    log_fail "API token expiration is enforced"
fi

echo
echo "=== API route alignment ==="
check_absent "Frontend does not call misspelled reset password route" 'reset_passwod' webvirtfrontend/apps/web/src
if rg -n -F "VITE_API_PREFIX || '/api/v1'" webvirtfrontend/apps/web/src/shared/constants.ts >/dev/null; then
    log_pass "Frontend API prefix has a safe default"
else
    log_fail "Frontend API prefix has a safe default"
fi
if rg -n -F "account/reset_password" webvirtfrontend/apps/web/src/entities/auth/api/reset-password.ts >/dev/null &&
    rg -n -F "reset_password/?$" webvirtbackend/account/urls.py >/dev/null; then
    log_pass "Reset password route matches backend"
else
    log_fail "Reset password route matches backend"
fi
if rg -n -F 'account/reset_password/${hash}' webvirtfrontend/apps/web/src/entities/auth/api/reset-password.ts >/dev/null &&
    rg -n -F 'reset_password/(?P<hash>\w+)/?$' webvirtbackend/account/urls.py >/dev/null &&
    rg -n -F 'path="/reset-password/:hash"' webvirtfrontend/apps/web/src/pages/index.tsx >/dev/null; then
    log_pass "Reset password hash route matches backend"
else
    log_fail "Reset password hash route matches backend"
fi
if rg -n "email_reset_password\.delay" webvirtbackend/account/serializers.py >/dev/null &&
    rg -n "reset_url" webvirtbackend/account/tasks.py webvirtbackend/templates/email/account-reset-password.html >/dev/null; then
    log_pass "Reset password email task is wired"
else
    log_fail "Reset password email task is wired"
fi
if rg -n "self\.is_email_verified = True" webvirtbackend/account/models.py >/dev/null &&
    rg -n -F "permission_classes = (AllowAny,)" webvirtbackend/account/views.py >/dev/null &&
    rg -n -F "prefixUrl: API_DOMAIN" webvirtfrontend/apps/web/src/entities/user/api/confirm-email.ts webvirtfrontend/apps/web/src/entities/user/api/resend-confirm-email.ts >/dev/null &&
    rg -n -F 'path="/confirm-email/:token"' webvirtfrontend/apps/web/src/pages/index.tsx >/dev/null; then
    log_pass "Email verification state and frontend route are aligned"
else
    log_fail "Email verification state and frontend route are aligned"
fi
if rg -n -F "admin_virtance_power_cycle" webvirtbackend/admin/virtance/urls.py webvirtbackend/templates/admin/virtance/virtance.html >/dev/null &&
    rg -n -F "admin_virtance_power_cyrcle" webvirtbackend/admin/virtance/urls.py >/dev/null; then
    log_pass "Admin power cycle route uses corrected name with legacy compatibility"
else
    log_fail "Admin power cycle route uses corrected name with legacy compatibility"
fi

echo
echo "=== Model and fixture integrity ==="
virtance_model_count="$({ rg -n '^class Virtance\(' webvirtbackend/virtance/models.py 2>/dev/null || true; } | wc -l | tr -d ' ')"
if [ "$virtance_model_count" = "1" ]; then
    log_pass "Virtance model is defined once"
else
    log_fail "Virtance model is defined once"
fi
check_absent "Virtance serializers do not use removed Image.virtance relation" 'Image\.objects\.filter\(virtance=' webvirtbackend/virtance/serializers.py
check_absent "Image list does not expose all non-LBaaS images across users" '~Q\(type=Image\.LBAAS\)' webvirtbackend/image/views.py
if rg -n -F "Q(type=Image.SNAPSHOT, user=user)" webvirtbackend/virtance/serializers.py >/dev/null &&
    rg -n -F "Q(type__in=user_types, user=user)" webvirtbackend/image/views.py >/dev/null; then
    log_pass "User-owned images are scoped before VM creation and listing"
else
    log_fail "User-owned images are scoped before VM creation and listing"
fi
if rg -n 'call_command\("loaddata", "initial_data"\)' webvirtbackend/webvirtcloud/management/commands/first_init_data.py >/dev/null; then
    log_pass "First init command loads existing initial_data fixtures"
else
    log_fail "First init command loads existing initial_data fixtures"
fi

echo
echo "=== Email templates ==="
check_absent "No placeholder or undefined email action links" 'apple\.com|undefined' webvirtfrontend/apps/email/build_production webvirtbackend/templates/email

echo
echo "=== Docker Compose config ==="
if docker compose version >/dev/null 2>&1; then
    (
        cd webvirtcloud
        created_env=false
        if [ ! -f env.local ]; then
            cp env.local.example env.local
            created_env=true
        fi
        trap 'if [ "$created_env" = true ]; then rm -f env.local; fi' EXIT
        docker compose config >/dev/null
    ) && log_pass "Production compose config"

    (
        cd webvirtbackend
        WEBVIRT_DEV_DB_PASSWORD=ci-db \
        WEBVIRT_DEV_DB_ROOT_PASSWORD=ci-root \
        WEBVIRT_DEV_RABBITMQ_PASSWORD=ci-rabbit \
        docker compose config >/dev/null
    ) && log_pass "Development compose config"
else
    log_warn "docker compose not available; skipping compose config checks"
fi

echo
echo "=== Python syntax ==="
python3 -m compileall -q -x '.*\/\.venv\/.*' webvirtbackend webvirtcompute prometheus-libvirt-exporter && log_pass "Python compileall"

echo
echo "=== IPv6 network handling ==="
python3 tests/test_ipv6_network.py && log_pass "IPv6 network allocation and configuration"

echo
echo "=== JSON syntax ==="
python3 -m json.tool prometheus-libvirt-exporter/grafana-dashboard.json >/dev/null && log_pass "Grafana dashboard JSON"
for fixture in webvirtbackend/*/fixtures/*.json; do
    python3 -m json.tool "$fixture" >/dev/null
done
log_pass "Backend fixture JSON"

rm -f /tmp/webvirtcloud-ci-match.txt

if [ "$ERRORS" -ne 0 ]; then
    echo "$ERRORS check(s) failed."
    exit 1
fi

echo "All checks passed."
