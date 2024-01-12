#!/usr/bin/env bash
# Script to clean up an IDP from a cluster using ocm
#
# Usage: ./setup-sso-idp.sh
#         Pass in variables below to override defaults

BASE_USERNAME="${BASE_USERNAME:-kuadrant}"
NUM_USER="${NUM_USER:-1}"
NAMESPACE="${NAMESPACE:-rhsso}"
REALM="${REALM:-keycloak-idp}"

format_user_name() {
  USER_NUM=$(printf "%02d" "$1") # Add leading zero to number
  USERNAME="$2$USER_NUM"         # Username combination of passed in username and number
}

## Delete keycloak resources
oc delete user --all
oc delete identity --all
for ((i = 1; i <= NUM_USER; i++)); do
  format_user_name $i "$BASE_USERNAME"
  oc delete keycloakuser "$REALM-$USERNAME" -n "$NAMESPACE"
done
oc delete keycloakclient "$REALM-client" -n "$NAMESPACE"
oc delete keycloakrealm "$REALM" -n "$NAMESPACE"

# If CLUSTER_ID is not passed, find out ID based on currently targeted server
CLUSTER_ID="${CLUSTER_ID:-$(ocm get clusters --parameter search="api.url like '$(oc whoami --show-server)'" 2>/dev/null | jq -r '.items[0].id')}"
IDP_NAME="${IDP_NAME:-keycloak-idp}"

# Delete identity provider in ocm
IDP_ID=$(ocm get "/api/clusters_mgmt/v1/clusters/$CLUSTER_ID/identity_providers" --parameter search="name is '$IDP_NAME'" | jq -r '.items[0].id')
ocm delete "/api/clusters_mgmt/v1/clusters/$CLUSTER_ID/identity_providers/$IDP_ID"
echo "Deleted IDP, $IDP_NAME, from cluster: $CLUSTER_ID"

# Wait for oauth to be updated
until ! oc get oauth cluster -o json | jq '.spec.identityProviders[].name' | grep -q -e "$REALM"; do
  echo "\"cluster\" OAuth configuration still contains our IDP, trying again in 10s"
  sleep 10
done

echo "Waiting for new configuration to propagate to OpenShift OAuth pods."
until [ $(oc get deployment oauth-openshift -n openshift-authentication -o json | jq '.status.unavailableReplicas') = "1" ]; do
  echo "\"oauth-openshift\" deployment is not updated yet, trying again in 10s"
  sleep 10
done

until [ $(oc get deployment oauth-openshift -n openshift-authentication -o json | jq '.status.unavailableReplicas') = "null" ]; do
  echo "\"oauth-openshift\" deployment is still updating, trying again in 10s"
  sleep 10
done