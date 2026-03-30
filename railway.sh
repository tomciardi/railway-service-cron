#!/bin/bash
set -euo pipefail

# Railway service scheduler — starts and stops services via the Railway GraphQL API.
# Usage: railway.sh [start|stop]

: "${RAILWAY_ACCOUNT_TOKEN:?RAILWAY_ACCOUNT_TOKEN is required}"
: "${RAILWAY_PROJECT_ID:?RAILWAY_PROJECT_ID is required}"
: "${RAILWAY_ENVIRONMENT_ID:?RAILWAY_ENVIRONMENT_ID is required}"
: "${SERVICES_ID:?SERVICES_ID is required}"

RAILWAY_API="https://backboard.railway.com/graphql/v2"

railway_api() {
  curl --silent --fail --max-time 30 \
    --url "$RAILWAY_API" \
    --header "Authorization: Bearer $RAILWAY_ACCOUNT_TOKEN" \
    --header "Content-Type: application/json" \
    --data "$1"
}

get_latest_deployment() {
  local service_id="$1"
  railway_api "{\"query\":\"query { deployments(first: 1, input: { projectId: \\\"$RAILWAY_PROJECT_ID\\\", environmentId: \\\"$RAILWAY_ENVIRONMENT_ID\\\", serviceId: \\\"$service_id\\\" }) { edges { node { id status service { name } } } } }\"}" \
    | jq -r '.data.deployments.edges[0].node // empty'
}

stop_service() {
  local service_id="$1"
  local info
  info=$(get_latest_deployment "$service_id")

  if [ -z "$info" ] || [ "$info" = "null" ]; then
    echo "No deployment found for service $service_id"
    return 1
  fi

  local name status dep_id
  name=$(echo "$info" | jq -r '.service.name // "unknown"')
  status=$(echo "$info" | jq -r '.status // "unknown"')
  dep_id=$(echo "$info" | jq -r '.id // empty')

  echo "[$name] status=$status"

  if [ "$status" = "REMOVED" ] || [ "$status" = "SLEEPING" ]; then
    echo "[$name] already stopped, skipping"
    return 0
  fi

  echo "[$name] stopping deployment $dep_id"
  railway_api "{\"query\":\"mutation { deploymentStop(id: \\\"$dep_id\\\") }\"}" \
    | jq '.data.deploymentStop // .errors'
}

start_service() {
  local service_id="$1"
  local info
  info=$(get_latest_deployment "$service_id")

  if [ -z "$info" ] || [ "$info" = "null" ]; then
    echo "No deployment found for service $service_id"
    return 1
  fi

  local name status dep_id
  name=$(echo "$info" | jq -r '.service.name // "unknown"')
  status=$(echo "$info" | jq -r '.status // "unknown"')
  dep_id=$(echo "$info" | jq -r '.id // empty')

  echo "[$name] status=$status"

  if [ "$status" = "SUCCESS" ]; then
    echo "[$name] already running, skipping"
    return 0
  fi

  if [ "$status" != "REMOVED" ] && [ "$status" != "SLEEPING" ]; then
    echo "[$name] not in a stoppable state ($status), skipping"
    return 0
  fi

  echo "[$name] redeploying $dep_id"
  railway_api "{\"query\":\"mutation { deploymentRedeploy(id: \\\"$dep_id\\\", usePreviousImageTag: true) { id status } }\"}" \
    | jq '.data.deploymentRedeploy // .errors'
}

# Validate token
echo "Validating Railway API token..."
response=$(railway_api "{\"query\":\"query { project(id: \\\"$RAILWAY_PROJECT_ID\\\") { name } }\"}")
project_name=$(echo "$response" | jq -r '.data.project.name // empty')

if [ -z "$project_name" ] || [ "$project_name" = "null" ]; then
  echo "Failed to authenticate — check RAILWAY_ACCOUNT_TOKEN and RAILWAY_PROJECT_ID"
  exit 1
fi
echo "Connected to project: $project_name"

# Execute
action="${1:?Usage: railway.sh [start|stop]}"

IFS=',' read -ra SERVICE_ARRAY <<< "$SERVICES_ID"
for service_id in "${SERVICE_ARRAY[@]}"; do
  service_id=$(echo "$service_id" | xargs)
  echo "---"
  case "$action" in
    start) start_service "$service_id" ;;
    stop)  stop_service "$service_id" ;;
    *)     echo "Unknown action: $action"; exit 1 ;;
  esac
done
