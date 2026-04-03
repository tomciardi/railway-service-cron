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
  local response http_code body
  response=$(curl --silent --max-time 30 \
    --write-out '\n%{http_code}' \
    --url "$RAILWAY_API" \
    --header "Authorization: Bearer $RAILWAY_ACCOUNT_TOKEN" \
    --header "Content-Type: application/json" \
    --data "$1")

  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')

  if [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
    echo "HTTP $http_code from Railway API" >&2
    echo "$body" >&2
    return 1
  fi

  local errors
  errors=$(echo "$body" | jq -r '.errors // empty')
  if [ -n "$errors" ] && [ "$errors" != "null" ]; then
    echo "GraphQL errors:" >&2
    echo "$errors" | jq '.' >&2
    return 1
  fi

  echo "$body"
}

get_latest_deployment() {
  local service_id="$1"
  local payload
  payload=$(jq -n \
    --arg pid "$RAILWAY_PROJECT_ID" \
    --arg eid "$RAILWAY_ENVIRONMENT_ID" \
    --arg sid "$service_id" \
    '{query: "query($pid: String!, $eid: String!, $sid: String!) { deployments(first: 1, input: { projectId: $pid, environmentId: $eid, serviceId: $sid }) { edges { node { id status service { name } } } } }", variables: {pid: $pid, eid: $eid, sid: $sid}}')

  railway_api "$payload" | jq -r '.data.deployments.edges[0].node // empty'
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
  local payload
  payload=$(jq -n --arg id "$dep_id" \
    '{query: "mutation($id: String!) { deploymentStop(id: $id) }", variables: {id: $id}}')

  railway_api "$payload" | jq '.data.deploymentStop // .errors'
}

start_service() {
  local service_id="$1"
  local info
  info=$(get_latest_deployment "$service_id")

  if [ -z "$info" ] || [ "$info" = "null" ]; then
    echo "No deployment found for service $service_id — triggering fresh deploy"
  else
    local name status
    name=$(echo "$info" | jq -r '.service.name // "unknown"')
    status=$(echo "$info" | jq -r '.status // "unknown"')
    echo "[$name] status=$status"

    if [ "$status" = "SUCCESS" ]; then
      echo "[$name] already running, skipping"
      return 0
    fi
  fi

  echo "Deploying service $service_id"
  local payload
  payload=$(jq -n \
    --arg sid "$service_id" \
    --arg eid "$RAILWAY_ENVIRONMENT_ID" \
    '{query: "mutation($sid: String!, $eid: String!) { serviceInstanceDeploy(serviceId: $sid, environmentId: $eid) }", variables: {sid: $sid, eid: $eid}}')

  railway_api "$payload" | jq '.data.serviceInstanceDeploy // .errors'
}

# Validate token
echo "Validating Railway API token..."
payload=$(jq -n --arg pid "$RAILWAY_PROJECT_ID" \
  '{query: "query($pid: String!) { project(id: $pid) { name } }", variables: {pid: $pid}}')

response=$(railway_api "$payload") || {
  echo "Failed to authenticate — check RAILWAY_ACCOUNT_TOKEN and RAILWAY_PROJECT_ID"
  exit 1
}

project_name=$(echo "$response" | jq -r '.data.project.name // empty')

if [ -z "$project_name" ] || [ "$project_name" = "null" ]; then
  echo "Token valid but project not found — check RAILWAY_PROJECT_ID"
  echo "Response: $response"
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
