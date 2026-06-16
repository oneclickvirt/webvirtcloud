# The original project has been deleted. This is only a personal archive.

# WebVirtBackend #

WebVirtBackend is an open-source Django-based backend for managing virtual machines in a KVM (Kernel-based Virtual Machine) environment. It is designed to be used with WebVirtCloud, a web interface for managing virtual machines. This project is packaged as a Docker Compose environment for easy deployment.

## Getting Started ##

### Prerequisites ###

* Docker
* Docker Compose

### Installation ###

1. Clone the repository
```bash
git clone https://github.com/oneclickvirt/webvirtcloud.git
```

2. Change into the cloned directory:
```bash
cd webvirtcloud/webvirtbackend/
```

3. Create local development secrets:
```bash
cp .env.example .env
# Edit .env and replace every change-me value before starting containers.
# Add any extra development hostnames to DJANGO_ALLOWED_HOSTS.
```

4. Build the Docker image:
```bash
docker compose build
```

5. Run the Docker container:
```bash
docker compose up -d
```

6. Run the database migrations:
```bash
docker compose exec backend python3 manage.py migrate
```

7. Load the initial data:
```bash
docker compose exec backend python3 manage.py loaddata initial_data
```

8. Create an admin user:
```bash
ADMIN_PASSWORD="$(openssl rand -hex 18)"
docker compose exec -T \
  -e WEBVIRT_ADMIN_EMAIL=admin@example.com \
  -e WEBVIRT_ADMIN_PASSWORD="$ADMIN_PASSWORD" \
  backend python3 manage.py first_init_data
echo "Admin password: $ADMIN_PASSWORD"
```

9. Access the admin site:
Open your web browser and go to `http://localhost:8000/admin/` and log in with the admin email and password you supplied.

## Settings ##

You can configure the backend by editing the `webvirtcloud/settings/local.py` file for modifying the default settings. The default settings are defined in `webvirtcloud/settings/base.py`.

## Development ##

Load the test user:

```bash
docker compose exec backend python3 manage.py loaddata account/fixtures/user.json
```

### Swagger ###

When `DJANGO_SETTINGS_MODULE=webvirtcloud.settings.develop`, Swagger API documentation is available at `http://localhost:8000/swagger/`. Production settings keep Swagger and ReDoc routes disabled.

### Credentials ###

The API endpoints are available at `http://localhost:8000/api/`. Use the token returned by the login endpoint or create a development token in your local database.

Example API requests:

```bash
curl -H "Authorization: Bearer <token>" http://localhost:8000/api/v1/virtances/
```

Tokens with an `expired` date earlier than the current local date are rejected by the API authentication layer. Password resets and password changes rotate all obtained login tokens for the affected user.

Development CORS is restricted to `DJANGO_CORS_ALLOWED_ORIGINS` by default. Set `DJANGO_CORS_ALLOW_ALL=true` only for isolated local debugging.

### Contributing ###

If you want to contribute to WebVirtBackend, please read the contributing guidelines first (Coming soon).

## License ##

WebVirtBackend is released under the Apache 2.0 Licence.
