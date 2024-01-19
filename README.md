# API Quickstart


## Introduction

This document will detail the setup of a reference architecture to support a number of API management use-cases connecting Kuadrant with other projects in the wider API management on Kubernetes ecosystem.

## Platform Engineer Steps (Part 1)


<!-- TODO: Copy formatting & env var info from the MGC Getting Started guide -->

Export the following env vars:

```
export KUADRANT_AWS_ACCESS_KEY_ID=<key_id>
export KUADRANT_AWS_SECRET_ACCESS_KEY=<secret>
export KUADRANT_AWS_REGION=<region>
export KUADRANT_AWS_DNS_PUBLIC_ZONE_ID=<zone>
export KUADRANT_ZONE_ROOT_DOMAIN=<domain>
```

Run the following command, choosing `aws` as the dns provider:

<!-- TODO: Change to a curl command that fetches everything remotely -->

```bash
`./quickstart.sh`
```

### Create a gateway

<!-- TODO: Create Gateway & TLSPolicy as part of quickstart, if possible -->


View the ManagedZone, Gateway and TLSPolicy:

```bash
kubectl --context kind-mgc-control-plane describe managedzone mgc-dev-mz -n multi-cluster-gateways
kubectl --context kind-mgc-control-plane describe gateway -n multi-cluster-gateways
kubectl --context kind-mgc-control-plane describe tlspolicy -n multi-cluster-gateways
```

### Guard Rails: Constraint warnings about missing policies ( DNS, AuthPolicy, RLP)
Running the quick start script above will bring up [Gatekeeper](https://open-policy-agent.github.io/gatekeeper/website/docs) and the following configurations: 

* Constraint Template
    * RequirePolicyTargetingGateway
* Constraints
    * require-dnspolicy-targeting-gateway (Warn)
    * require-authpolicy-targeting-gateway (Warn)
    * require-ratelimitpolicy-targeting-gateway (Warn)
* Mutation
    * authpolicy-mutation

To get the above constraints and constraint templates run:
```bash
kubectl --context kind-mgc-control-plane get constraint -A  -o yaml
kubectl --context kind-mgc-control-plane get constrainttemplates -A  -o yaml
kubectl --context kind-mgc-control-plane get mutations -A  -o yaml

```
**Note:** :exclamation: Since a gateway has been created the constraints will be active and will be in violation until the polices are created. 

#### Grafana dashboard view
To get a top level view of the constraints in violation, the platform engineer dashboard can be used. This can be accessed by:
* Following the grafana link `https://grafana.172.31.0.2.nip.io`

Grafana will be set up with a **username** `admin` and **password** `admin` use these to login to see the dashboards.

The few most relevant for a platform engineer is called `Stitch: Platform Engineer Dashboard` or `Stitch: Gatekeeper`

### Create missing Policies

#### DNSPolicy
Create a DNSPolicy:

```bash
kubectl --context kind-api-control-plane apply -f - <<EOF
apiVersion: kuadrant.io/v1alpha1
kind: DNSPolicy
metadata:
  name: prod-web
  namespace: multi-cluster-gateways
spec:
  targetRef:
    name: prod-web
    group: gateway.networking.k8s.io
    kind: Gateway
  loadBalancing:
    geo:
      defaultGeo: EU
EOF
```
####  Route 53 DNS Zone

When the DNS Policy has been created, a DNS record custom resource will also be created in the cluster resulting in records being created in your AWS Route53. Please navigate to Route53 and ensure they are present. The record will have `petstore` in its name

#### RateLimitPolicy 
Create a Gateway-wide RateLimitPolicy

```bash
kubectl --context kind-api-control-plane apply -f - <<EOF
apiVersion: kuadrant.io/v1beta2
kind: RateLimitPolicy
metadata:
  name: prod-web
  namespace: multi-cluster-gateways
spec:
  targetRef:
    name: prod-web
    group: gateway.networking.k8s.io
    kind: Gateway
  limits:
    "global":
      rates:
      - limit: 10
        duration: 10
        unit: second
EOF
```
#### Authpolicy
Create a Gateway-wide AuthPolicy

```bash
kubectl --context kind-api-control-plane apply -f - <<EOF
apiVersion: kuadrant.io/v1beta2
kind: AuthPolicy
metadata:
  name: gw-auth
  namespace: kuadrant-multi-cluster-gateways
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
```
### Platform Overview

Since we have created all the policies that Gatekeeper had the guardrails around, you should no longer see any constraints in violation. To check this from a high level go back to the dashboards from the previous step and ensure the violations are no longer present.

`https://grafana.172.31.0.2.nip.io`

As we have created these policies the dashboard will be populated with more useful data including information about:
* Gateways & Policies
* TLSPolicy, DNSPolicy, AuthPolicy and RateLimitPolicy

In the next step as a App developer you will get additional info like API summaries and route policies.

## App Developer Steps

### API Setup

<!-- TODO: Make this repo public somewhere -->

Fork and clone the Petstore App at https://github.com/Kuadrant/api-poc-petstore.

```bash
cd ~
git clone git@github.com:<your_github_username>/api-poc-petstore
```

Then deploy it to the first workload cluster:

```bash
cd ~/api-poc-petstore
kubectl --context kind-api-workload-1 apply -k ./resources/
```

Configure the app `REGION` to be `eu`:

```bash
kubectl --context kind-api-workload-1 apply -k ./resources/local-cluster/
```

TODO

* Open api spec in apicurio studio, showing x-kuadrant extensions & making requests (with swagger) to the show rate limit policy
* Modify x-kuadrant extension to change rate limit
* Export spec and generate resources with kuadrantctl
* Apply generated resources to petstore app in cluster
* Back in apicurio studio, modify x-kuadrant extension to add auth to /store/inventory endpoint
* Export spec, generate resources and reapply to cluster
* Verify auth policy via swagger

### Multicluster Bonanza

TODO

Deploy the petstore to 2nd cluster:

```bash
cd ~/api-poc-petstore
kubectl --context kind-api-workload-2 apply -k ./resources/
```

Configure the app `REGION` to be `us`:

```bash
kubectl --context kind-api-workload-2 apply -k ./resources/spoke-cluster/
```

e.g.

```bash
kubectl --context kind-mgc-control-plane patch placement petstore -n argocd --type='json' -p='[{"op": "add", "path": "/spec/clusterSets/-", "value": "petstore-region-us"}, {"op": "replace", "path": "/spec/numberOfClusters", "value": 2}]'
```

Describe the DNSPolicy

```bash
kubectl --context kind-mgc-control-plane describe dnspolicy prod-web -n multi-cluster-gateways
```

Show ManagedCluster labelling

```bash
kubectl --context kind-mgc-control-plane get managedcluster -A -o custom-columns="NAME:metadata.name,URL:spec.managedClusterClientConfigs[0].url,REGION:metadata.labels.kuadrant\.io/lb-attribute-geo-code"
```

Show DNS resolution per geo region

TODO

Show rate limiting working on both clusters/apps.

### App Developer Overview: API traffic & impact of AuthPolicy & Rate Limit Policy

To view the App developer dashboards the same Grafana will be used from the platform engineer steps above:
`https://grafana.172.31.0.2.nip.io`

The most relevant for a app developer is `Stitch: App Developer Dashboard` 
You should see panels about API's including:

* Request and error rates
* API summaries
* API request summaries
* API duration

All corresponding to our HTTPRoute coming from our OAS spec

## Platform Engineer Steps (Part 2)

### Platform Overview

Now that the app developer has deployed their app, new metrics and data is now available in the platform engineer dashboard seen in the previous step `https://grafana.172.31.0.2.nip.io`. Including:

* Gateways & both route and gateway policies 
* Constraints & Violations (Should be no violations present)
* APIs Summary 