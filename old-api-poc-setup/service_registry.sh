#!/bin/bash

installServiceRegistry() {
  # kubectl get packagemanifests service-registry-operator -o jsonpath="{range .status.channels[*]}Channel: {.name} currentCSV: {.currentCSV}{'\n'}{end}"
  # kubectl get packagemanifests service-registry-operator -o jsonpath={.status.catalogSource}
  # kubectl get packagemanifests service-registry-operator -o jsonpath={.status.catalogSourceNamespace}

  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: service-registry
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: service-registry
  namespace: openshift-operators
spec:
  channel: 2.x
  installPlanApproval: Automatic
  name: service-registry-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  startingCSV: service-registry-operator.v2.2.3
EOF

  kubectl wait csv/service-registry-operator.v2.2.3-0.1698369839.p --timeout=300s --for "jsonpath=status.phase=Succeeded"

  # Extract base64-encoded values from the secret
  PG_DB_NAME=$(kubectl get secret -n openshift-operators service-registry-postgres-pguser-super-service-registry-user -o jsonpath='{.data.dbname}')
  PG_HOST=$(kubectl get secret -n openshift-operators service-registry-postgres-pguser-super-service-registry-user -o jsonpath='{.data.host}')
  PG_PASSWORD=$(kubectl get secret -n openshift-operators service-registry-postgres-pguser-super-service-registry-user -o jsonpath='{.data.password}')
  PG_USER=$(kubectl get secret -n openshift-operators service-registry-postgres-pguser-super-service-registry-user -o jsonpath='{.data.user}')
  PG_PORT=$(kubectl get secret -n openshift-operators service-registry-postgres-pguser-super-service-registry-user -o jsonpath='{.data.port}')


  # Decode the values
  PG_DB_NAME=$(echo "$PG_DB_NAME" | base64 --decode)
  PG_HOST=$(echo "$PG_HOST" | base64 --decode)
  PG_PASSWORD=$(echo "$PG_PASSWORD" | base64 --decode)
  PG_USER=$(echo "$PG_USER" | base64 --decode)
  PG_PORT=$(echo "$PG_PORT" | base64 --decode)

  echo "PG_DB_NAME: $PG_DB_NAME"
  echo "PG_HOST: $PG_HOST"
  echo "PG_PASSWORD: $PG_PASSWORD"
  echo "PG_USER: $PG_USER"
  echo "PG_PORT: $PG_PORT"

  ingressControllerHost=$(kubectl --context $CONTEXT get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.status.domain}')

  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: registry.apicur.io/v1
kind: ApicurioRegistry
metadata:
  name: apicurioregistry
  namespace: service-registry
spec:
  configuration:
    persistence: "sql"
    sql:
      dataSource:
        url: "jdbc:postgresql://${PG_HOST}:${PG_PORT}/${PG_DB_NAME}"
        userName: "${PG_USER}"
        password: "${PG_PASSWORD}"
  deployment:
    host: service-registry.$ingressControllerHost
    replicas: 1
EOF

  kubectl --context $CONTEXT wait apicurioregistry/apicurioregistry -n service-registry --timeout=300s --for="condition=Ready=True"

  kubectl --context $CONTEXT apply -f - <<EOF
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  name: apicurioregistry-https
  namespace: service-registry
spec:
  host: service-registry.$ingressControllerHost
  to:
    kind: Service
    name: apicurioregistry-service
    weight: 100
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
EOF
}

showServiceRegistryDetails() {
  registryHost=$(kubectl --context $CONTEXT get route apicurioregistry-https -n service-registry -o=jsonpath='{.spec.host}')
  echo "Service Registry: https://$registryHost"
  echo ""
}
