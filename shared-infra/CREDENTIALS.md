# Shared Infrastructure — Credentials & Connection Reference
# WSL2 IP: 192.168.16.153
# Port range: 13000–13900

## PostgreSQL
- Host (Windows):     192.168.16.153:13000
- Host (Docker apps): postgres-shared:5432
- Username:           admin
- Password:           admin
- Default database:   postgres
- Per-app databases:  CREATE DATABASE appname; (one per app)

## Redis
- Host (Windows):     192.168.16.153:13050
- Host (Docker apps): redis-shared:6379
- Password:           none
- Per-app isolation:  use key prefixes (e.g. daytona:*, myapp:*)

## MinIO (S3)
- S3 API (Windows):     http://192.168.16.153:13100
- S3 API (Docker apps): http://minio-shared:9000
- Console URL:          http://192.168.16.153:13150
- Access Key:           minioadmin
- Secret Key:           minioadmin
- Per-app isolation:    create one bucket per app

## MailDev (SMTP)
- Web UI:             http://192.168.16.153:13200  (no login)
- SMTP (Windows):     192.168.16.153:13250
- SMTP (Docker apps): maildev-shared:1025
- Auth:               none — all mail captured, nothing delivered externally

## Dex (OIDC / OAuth2)
- OIDC URL:           http://192.168.16.153:13300/dex
- Internal URL:       http://dex-shared:5556/dex
- Test user email:    admin@local.dev
- Test user password: password
- Config file:        ./dex/config.yaml (add one staticClient per app)

## Jaeger (Tracing UI)
- Web UI:             http://192.168.16.153:13350  (no login)

## OpenTelemetry Collector
- gRPC (Windows):     192.168.16.153:13400
- gRPC (Docker apps): otel-collector-shared:4317
- HTTP (Windows):     http://192.168.16.153:13450
- HTTP (Docker apps): http://otel-collector-shared:4318
- App env var:        OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-shared:4318

## Prometheus
- Web UI:             http://192.168.16.153:13500  (no login)
- Internal URL:       http://prometheus-shared:9090
- Config file:        ./prometheus/prometheus.yml (add scrape targets per app)

## Grafana
- Web UI:             http://192.168.16.153:13550
- Username:           admin
- Password:           admin
- Prometheus source:  http://prometheus-shared:9090

## Docker Registry
- API URL (Windows):      http://192.168.16.153:13600
- API URL (Docker apps):  http://registry-shared:5000
- Web UI:                 http://192.168.16.153:13650  (no login)
- Push image:             docker tag myimage 192.168.16.153:13600/myimage:tag
- Pull image:             docker pull 192.168.16.153:13600/myimage:tag

## Reserved ports (free for future services)
- 13700, 13750, 13800, 13850, 13900
