# Railway Service Cron

Lightweight Alpine container that starts and stops Railway services on a cron schedule. Uses Railway's GraphQL API with [supercronic](https://github.com/aptible/supercronic) for container-friendly cron execution.

Based on [smolpaw/railway-service-cron](https://github.com/smolpaw/railway-service-cron) (MIT), rewritten with:
- `deploymentStop` instead of `deploymentRemove` (graceful vs destructive)
- Crontab generated at runtime (schedule changes don't require a rebuild)
- Pinned Alpine version and strict env validation

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `RAILWAY_ACCOUNT_TOKEN` | Yes | Account token from https://railway.app/account/tokens |
| `RAILWAY_PROJECT_ID` | Yes | Project ID (from project settings URL) |
| `RAILWAY_ENVIRONMENT_ID` | Yes | Environment ID (from environment settings URL) |
| `SERVICES_ID` | Yes | Comma-separated service IDs to manage |
| `START_SCHEDULE` | Yes | Cron expression for starting services |
| `STOP_SCHEDULE` | Yes | Cron expression for stopping services |
| `TZ` | No | Timezone (default: UTC) |

Railway variable references (`${{VAR}}`) make configuration clean: `RAILWAY_PROJECT_ID` and `RAILWAY_ENVIRONMENT_ID` are built-in and available automatically. `RAILWAY_ACCOUNT_TOKEN` and `SERVICES_ID` can be set as shared variables once and referenced across services — no extra work beyond defining them.

## Deployment

Deploy as a separate Railway service in the same project. No subdirectory configuration needed — the root of this repo is the build context.

Example config for running services 9–5 on weekdays:

```
START_SCHEDULE=0 9 * * 1-5
STOP_SCHEDULE=0 17 * * 1-5
TZ=America/New_York
```

## How It Works

- `startup.sh` generates a crontab from `START_SCHEDULE` and `STOP_SCHEDULE`, then runs supercronic
- On each cron tick, `railway.sh` queries the latest deployment status via the GraphQL API
- Only starts stopped/sleeping services, only stops running services — no unnecessary API calls
- All output goes to stdout for Railway's log viewer
