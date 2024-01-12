#!/bin/bash

showSSODetails() {
  kubectl wait csv/rhsso-operator.7.6.5-opr-004 -n rhsso --timeout=300s --for "jsonpath=status.phase=Succeeded"
  kubectl --context $CONTEXT wait pods -l app=keycloak --for=condition=Ready --timeout=300s -n rhsso
  echo "Keycloak:"
  echo "https://$(kubectl --context $CONTEXT get route keycloak -n rhsso -o jsonpath='{.spec.host}')"

  KC_USER=$(kubectl --context $CONTEXT get secret -n rhsso credential-keycloak -o jsonpath='{.data.ADMIN_USERNAME}' | base64 --decode)
  KCPASS=$(kubectl --context $CONTEXT get secret -n rhsso credential-keycloak -o jsonpath='{.data.ADMIN_PASSWORD}' | base64 --decode)
  echo "User: $KC_USER, Password: $KCPASS"
  echo ""
}
