#!/bin/bash

configureAuthPolicy() {
  # Optional - this may be done live during a demo
  # https://gist.github.com/guicassolato/7dc98df842a89657050514d31daadaa3

  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: toystore
  labels:
    app: toystore
spec:
  selector:
    matchLabels:
      app: toystore
  template:
    metadata:
      labels:
        app: toystore
    spec:
      containers:
        - name: toystore
          image: quay.io/3scale/authorino:echo-api
          env:
            - name: PORT
              value: "3000"
          ports:
            - containerPort: 3000
              name: http
  replicas: 1
---
apiVersion: v1
kind: Service
metadata:
  name: toystore
spec:
  selector:
    app: toystore
  ports:
    - name: http
      port: 80
      protocol: TCP
      targetPort: 3000
EOF

  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: toystore
spec:
  parentRefs:
  - kind: Gateway
    name: prod-web
    namespace: kuadrant-multi-cluster-gateways
  hostnames:
  - toystore.$ZONE_DOMAIN
  rules:
  - matches:
    - method: GET
      path:
        type: PathPrefix
        value: "/cars"
    - method: GET
      path:
        type: PathPrefix
        value: "/dolls"
    backendRefs:
    - name: toystore
      port: 80
  - matches:
    - path:
        type: PathPrefix
        value: "/admin"
    backendRefs:
    - name: toystore
      port: 80
EOF

  sleep 10 #TODO: wait

  curl -i https://toystore.$ZONE_DOMAIN/cars
  curl -i https://toystore.$ZONE_DOMAIN/dolls
  curl -i https://toystore.$ZONE_DOMAIN/admin

  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: kuadrant.io/v1beta2
kind: AuthPolicy
metadata:
  name: toystore
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: toystore
  rules:
    authentication:
      "api-key-authn":
        apiKey:
          selector: {}
        credentials:
          authorizationHeader:
            prefix: APIKEY
    authorization:
      "only-admins":
        opa:
          rego: |
            groups := split(object.get(input.auth.identity.metadata.annotations, "kuadrant.io/groups", ""), ",")
            allow { groups[_] == "admins" }
        routeSelectors:
        - matches:
          - path:
              type: PathPrefix
              value: "/admin"
EOF

  kubectl --context $CONTEXT apply -f -<<EOF
apiVersion: v1
kind: Secret
metadata:
  name: api-key-regular-user
  labels:
    authorino.kuadrant.io/managed-by: authorino
stringData:
  api_key: iamaregularuser
type: Opaque
---
apiVersion: v1
kind: Secret
metadata:
  name: api-key-admin-user
  labels:
    authorino.kuadrant.io/managed-by: authorino
  annotations:
    kuadrant.io/groups: admins
stringData:
  api_key: iamanadmin
type: Opaque
EOF

  curl -I -s -X GET https://toystore.stitch2.hcpapps.net/cars
  # HTTP/1.1 401 Unauthorized

  curl -I -s -X GET -H 'Authorization: APIKEY iamaregularuser' https://toystore.stitch2.hcpapps.net/cars
  # HTTP/1.1 200 OK

 / curl -I -s -X GET -H 'Authorization: APIKEY iamaregularuser' https://toystore.stitch2.hcpapps.net/admin
  # HTTP/1.1 403 Forbidden


  curl -I -s -X GET -H 'Authorization: APIKEY iamanadmin' https://toystore.stitch2.hcpapps.net/admin
  # HTTP/1.1 403 Forbidden


#   echo "Setup a deny-all policy for the entire Gateway"

#   kubectl --context $CONTEXT -n kuadrant-multi-cluster-gateways delete -f - <<EOF
# apiVersion: kuadrant.io/v1beta2
# kind: AuthPolicy
# metadata:
#   name: gw-auth
# spec:
#   targetRef:
#     group: gateway.networking.k8s.io
#     kind: Gateway
#     name: prod-web
#   rules:
#     authorization:
#       deny-all:
#         opa:
#           rego: "allow = false"
#     response:
#       unauthorized:
#         headers:
#           "content-type":
#             value: application/json
#         body:
#           value: |
#             {
#               "error": "Forbidden",
#               "message": "Access denied by default by the gateway operator. If you are the administrator of the service, create a specific auth policy for the route."
#             }
# EOF
}


configureJWTAuthPolicy() {
  # https://docs.kuadrant.io/kuadrant-operator/doc/user-guides/authenticated-rl-with-jwt-and-k8s-authnz/#4-enforce-authentication-and-authorization-for-the-toy-store-api
  kubectl --context $CONTEXT apply -f - <<EOF
apiVersion: kuadrant.io/v1beta2
kind: AuthPolicy
metadata:
  name: toystore-protection
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: toystore
  rules:
    authentication:
      "keycloak-users":
        jwt:
          issuerUrl: https://keycloak-rhsso.apps.stitchpoc2.vtdv.p1.openshiftapps.com/auth/realms/kuadrant
      "k8s-service-accounts":
        kubernetesTokenReview:
          audiences:
          - https://kubernetes.default.svc.cluster.local
        overrides:
          "sub":
            selector: auth.identity.user.username
    authorization:
      "k8s-rbac":
        kubernetesSubjectAccessReview:
          user:
            selector: auth.identity.sub
    response:
      success:
        dynamicMetadata:
          "identity":
            json:
              properties:
                "userid":
                  selector: auth.identity.sub
EOF

  curl -I -s -X GET https://toystore.stitch2.hcpapps.net/cars
  # HTTP/2 401
  # www-authenticate: Bearer realm="k8s-service-accounts"
  # www-authenticate: Bearer realm="keycloak-users"
  # x-ext-auth-reason: {"k8s-service-accounts":"credential not found","keycloak-users":"credential not found"}
  # date: Wed, 01 Nov 2023 15:13:20 GMT
  # server: istio-envoy

  ACCESS_TOKEN=$(curl https://keycloak-rhsso.apps.stitchpoc2.vtdv.p1.openshiftapps.com/auth/realms/kuadrant/protocol/openid-connect/token -s -d 'grant_type=password' -d 'client_id=demo' -d 'username=john' -d 'password=p' -d 'scope=openid' | jq -r .access_token)
  echo $ACCESS_TOKEN

  curl -H "Authorization: Bearer $ACCESS_TOKEN" -I -s -X GET https://toystore.stitch2.hcpapps.net/cars
  # HTTP/2 200
  # content-type: application/json
  # server: istio-envoy
  # date: Thu, 02 Nov 2023 16:48:28 GMT
  # content-length: 3740
  # x-envoy-upstream-service-time: 2
}


addGatewayDenyAll() {
  kubectl --context $CONTEXT -n kuadrant-multi-cluster-gateways apply -f - <<EOF
apiVersion: kuadrant.io/v1beta2
kind: AuthPolicy
metadata:
  name: gw-auth
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: prod-web
  rules:
    authorization:
      deny-all:
        opa:
          rego: "allow = false"
    response:
      unauthorized:
        headers:
          "content-type":
            value: application/json
        body:
          value: |
            {
              "error": "Forbidden",
              "message": "Access denied by default by the gateway operator. If you are the administrator of the service, create a specific auth policy for the route."
            }
EOF
}