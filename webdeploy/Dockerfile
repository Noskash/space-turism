# Public web build of the game on Railway (service "web" in project space-turism-relay).
# Static files only: Caddy serves site/ (copied in by deploy.sh) on Railway's $PORT over its HTTPS domain.
FROM caddy:2.8.4-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY site /srv
