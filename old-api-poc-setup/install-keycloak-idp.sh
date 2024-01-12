#!/usr/bin/env bash
# Script to use keycloak as an IDP for an OSD cluster using ocm

## Usage: ./setup-sso-idp.sh
#         Pass in variables below to override defaults

set -e
set -o pipefail

ADMIN_CRED_SECRET="${ADMIN_CRED_SECRET:-credential-keycloak}"
KEYCLOAK_LABEL="${KEYCLOAK_LABEL:-sso}"
NAMESPACE="${NAMESPACE:-rhsso}"
REALM="${REALM:-keycloak-idp}"
REALM_DISPLAY_NAME="${REALM_DISPLAY_NAME:-Keycloak IDP}"

BASE_USERNAME="${BASE_USERNAME:-kuadrant}"
NUM_USER="${NUM_USER:-1}"
PASSWORD="${PASSWORD:-$(openssl rand -base64 12)}"

# function to format user name depending on how many are created
format_user_name() {
  USER_NUM=$(printf "%02d" "$1") # Add leading zero to number
  USERNAME="$2$USER_NUM"         # Username combination of passed in username and number
}

# Create sample normal users
create_users() {
  if ((NUM_USER <= 0)); then
    echo "Skipping regular user creation"
    return
  fi

  echo "Creating keyclaok users"
  for ((i = 1; i <= NUM_USER; i++)); do
    format_user_name $i "$BASE_USERNAME"
    oc process -p NAMESPACE="$NAMESPACE" -p REALM="$REALM" -p PASSWORD="$PASSWORD" -p USERNAME="$USERNAME" -p FIRSTNAME="$BASE_USERNAME" -p LASTNAME="User ${USER_NUM}" -f "${BASH_SOURCE%/*}/keycloak-user-template.yml" | oc apply -f -
  done
}

install_via_ocm() {
  echo "Cluster ID: $CLUSTER_ID"

  IDP_ID=$(ocm get "/api/clusters_mgmt/v1/clusters/$CLUSTER_ID/identity_providers" | jq -r "select(.size > 0) | .items[] | select( .name == \"$REALM\") | .id")
  if [[ ${IDP_ID} ]]; then
    echo "$REALM IDP is already present in OCM configuration."
    echo "OpenShift resources from keycloak-idp-template.yml will not be applied"
    echo "If you would like to re-apply any resources, delete the IDP from OCM and re-run this script."
    echo "To delete IDP execute: ocm delete \"/api/clusters_mgmt/v1/clusters/$CLUSTER_ID/identity_providers/$IDP_ID\""
  else
    # Delete any keycloak client of the same name to allow regenerating correct client secret for keycloak client
    oc delete keycloakclient "$REALM-client" -n "$NAMESPACE" --ignore-not-found=true

    # apply KeycloakRealm and KeycloakClient from a template
    oc process -p OAUTH_URL="$OAUTH_URL" -p NAMESPACE="$NAMESPACE" -p REALM="$REALM" -p REALM_DISPLAY_NAME="$REALM_DISPLAY_NAME" -p CLIENT_SECRET="$CLIENT_SECRET" -p KEYCLOAK_LABEL="$KEYCLOAK_LABEL" -f "${BASH_SOURCE%/*}/keycloak-idp-template.yml" | oc apply -f -

    sed "s|REALM|$REALM|g; s|KEYCLOAK_URL|$KEYCLOAK_URL|g; s|CLIENT_SECRET|$CLIENT_SECRET|g" "${BASH_SOURCE%/*}/ocm-idp-template.json" | ocm post "/api/clusters_mgmt/v1/clusters/$CLUSTER_ID/identity_providers"
    echo "$REALM IDP added into OCM configuration"
  fi

  # create KeycloakUsers
  create_users

  # Wait for oauth to be updated
  until oc get oauth cluster -o json | jq '.spec.identityProviders[].name' | grep -q "$REALM"; do
    echo "\"cluster\" OAuth configuration does not contain our IDP yet, trying again in 10s"
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
}

echo "User password set to \"${PASSWORD}\""
CLIENT_SECRET=$(openssl rand -base64 20)
OAUTH_URL=https://$(oc get route oauth-openshift -n openshift-authentication -o json | jq -r .spec.host)
KEYCLOAK_URL=https://$(oc get route keycloak -n "$NAMESPACE" -o json | jq -r .spec.host)
echo "Keycloak console: $KEYCLOAK_URL/auth/admin/master/console/#/realms/$REALM"
echo "Keycloack credentials: admin / $(oc get secret "$ADMIN_CRED_SECRET" -n "$NAMESPACE" -o json | jq -r .data.ADMIN_PASSWORD | base64 --decode)"
echo "Keycloak realm: $REALM"

# If CLUSTER_ID is not passed, find out ID based on currently targeted server
set +e # ignore errors in environments without ocm command
CLUSTER_ID="${CLUSTER_ID:-$(ocm get clusters --parameter search="api.url like '$(oc whoami --show-server )'" 2>/dev/null | jq -r .items[0].id)}"
set -e

# If CLUSETER_ID is detected
if [[ ${CLUSTER_ID} ]]; then
  install_via_ocm
else
  echo "Ensure you are an owner of the OSD cluster, logged into the correct environemt via ocm and also to the cluster via oc"
  exit 1
fi