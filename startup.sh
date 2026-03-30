#!/bin/sh
set -eu

: "${START_SCHEDULE:?START_SCHEDULE is required (cron expression)}"
: "${STOP_SCHEDULE:?STOP_SCHEDULE is required (cron expression)}"

# Generate crontab at runtime so schedule changes don't require a rebuild.
cat > /app/crontab <<EOF
$START_SCHEDULE /usr/local/bin/railway.sh start
$STOP_SCHEDULE /usr/local/bin/railway.sh stop
EOF

echo "Railway Service Cron"
echo "  TZ:    ${TZ:-UTC}"
echo "  Start: $START_SCHEDULE"
echo "  Stop:  $STOP_SCHEDULE"
echo "  IDs:   $SERVICES_ID"

exec /usr/local/bin/supercronic /app/crontab
