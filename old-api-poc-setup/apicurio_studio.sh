#!/bin/bash

installApicurioStudio() {
  APICURIO_NS="apicurio"
  RHSSO_NS="rhsso"
  REALM_NAME="apicurio"

  # https://github.com/apicurio/apicurio-studio-operator
  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $APICURIO_NS
---
EOF

  kubectl --context $CONTEXT apply -f https://raw.githubusercontent.com/Apicurio/apicurio-studio-operator/main/deploy/crd/apicuriostudios.studio.apicur.io-v1.yml
  kubectl --context $CONTEXT apply -f https://raw.githubusercontent.com/Apicurio/apicurio-studio-operator/main/deploy/service_account.yaml -n $APICURIO_NS
  kubectl --context $CONTEXT apply -f https://raw.githubusercontent.com/Apicurio/apicurio-studio-operator/main/deploy/role.yaml -n $APICURIO_NS
  kubectl --context $CONTEXT apply -f https://raw.githubusercontent.com/Apicurio/apicurio-studio-operator/main/deploy/role_binding.yaml -n $APICURIO_NS

  # Operator
  kubectl --context $CONTEXT apply -f https://raw.githubusercontent.com/Apicurio/apicurio-studio-operator/main/deploy/operator.yaml -n $APICURIO_NS
  kubectl --context $CONTEXT get pods -n $APICURIO_NS

  # Assumes keycloak has already been installed
  KEYCLOAK_URL=$(kubectl --context $CONTEXT get route keycloak -n $RHSSO_NS -o json | jq -r '.status.ingress[0].host')
  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: studio.apicur.io/v1alpha1
kind: ApicurioStudio
metadata:
  name: apicurio-studio
  namespace: $APICURIO_NS
spec:
  name: apicurio-studio
  keycloak:
    install: false
    realm: $REALM_NAME
    url: $KEYCLOAK_URL
EOF

  # Wait a small bit for routes to be available
  until [ $(kubectl --context $CONTEXT get routes -n $APICURIO_NS -o json | jq '.items | length') = 3 ]; do
    echo "Apicurio studio ui route is not available yet, trying again in 1s"
    sleep 1
  done

  APICURIO_STUDIO_ROUTE="https://$(kubectl --context $CONTEXT get route apicurio-studio-ui -n $APICURIO_NS -o jsonpath='{.spec.host}')"

  # Create Apicurio KeyCloak Realm CR with clients
  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: keycloak.org/v1alpha1
kind: KeycloakRealm
metadata:
  name: $REALM_NAME
  namespace: $RHSSO_NS
  labels:
    sso: $REALM_NAME
spec:
  instanceSelector:
    matchLabels:
      app: sso
  realm:
    enabled: true
    id: $REALM_NAME
    realm: $REALM_NAME
    registrationAllowed: true
    registrationEmailAsUsername: true
    rememberMe: true
    sslRequired: none
    clients:
      - clientId: apicurio-api
        secret: $(openssl rand -base64 20)
        clientAuthenticatorType: client-secret
        bearerOnly: true
        standardFlowEnabled: true
        directAccessGrantsEnabled: true
        defaultClientScopes:
          - role_list
          - profile
          - email
        optionalClientScopes:
          - address
          - phone
          - offline_access
      - clientId: apicurio-studio
        secret: $(openssl rand -base64 20)
        clientAuthenticatorType: client-secret
        publicClient: true
        standardFlowEnabled: true
        directAccessGrantsEnabled: true
        rootUrl: $APICURIO_STUDIO_ROUTE
        redirectUris:
          - $APICURIO_STUDIO_ROUTE/*
        baseUrl: $APICURIO_STUDIO_ROUTE
        webOrigins: 
          - "+"
        attributes:
          saml.assertion.signature: 'false'
          saml.force.post.binding: 'false'
          saml.multivalued.roles: 'false'
          saml.encrypt: 'false'
          saml_force_name_id_format: 'false'
          saml.client.signature: 'false'
          saml.authnstatement: 'false'
          saml.server.signature: 'false'
          saml.server.signature.keyinfo.ext: 'false'
          saml.onetimeuse.condition: 'false'
        defaultClientScopes:
          - role_list
          - profile
          - email
        optionalClientScopes:
          - address
          - phone
          - offline_access
EOF

  kubectl --context $CONTEXT wait pods -l app=apicurio-studio --for=condition=Ready --timeout=300s -n $APICURIO_NS
  showApicurioStudioDetails
}

showApicurioStudioDetails() {
  echo "Apicurio Studio: https://$(kubectl --context $CONTEXT get route apicurio-studio-ui -n apicurio -o jsonpath='{.spec.host}')"
  echo "Signup and login with your own account"

  echo "Apicurio Studio Keycloak Admin details is the same as the existing Keycloak Admin details"
}

cleanUpApicurio() {
  kubectl --context $CONTEXT delete keycloakrealm apicurio -n rhsso 
  kubectl --context $CONTEXT delete apicuriostudio apicurio-studio -n apicurio
  kubectl --context $CONTEXT delete namespace apicurio
}