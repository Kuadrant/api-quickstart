# API Quickstart

## Introduction

This document details how to setup a local reference architecture, and design and deploy an API. This will show the following API management features in a kube native environment using Kuadrant and other open source tools:

- API design
- API security and access control
- API monitoring
- Traffic management and scalability

The sections in this document are grouped by the persona that is typically associated with the steps in that section. The 3 personas are:

- The *platform engineer*, who provides and maintains a platform for application developers,
- the *application developer*, who designs, builds and maintains applications and APIs,
- and the *api consumer*, who makes API calls to the API

## Pre-requisities

- `kubectl`: https://kubernetes.io/docs/reference/kubectl/
- `kustomize`: https://kustomize.io/
- An [AWS account](https://aws.amazon.com/) with a Secret Access Key and Access Key ID. You will also need to a [Route 53](https://docs.aws.amazon.com/route53/) zone.

## (Platform engineer) Platform Setup

Export the following env vars:

```bash
export KUADRANT_AWS_ACCESS_KEY_ID=<key_id>
export KUADRANT_AWS_SECRET_ACCESS_KEY=<secret>
export KUADRANT_AWS_REGION=<region>
export KUADRANT_AWS_DNS_PUBLIC_ZONE_ID=<zone>
export KUADRANT_ZONE_ROOT_DOMAIN=<domain>
```

Clone the api-quickstart repo and run the quickstart script:

```bash
git clone git@github.com:Kuadrant/api-quickstart.git
cd api-quickstart
./quickstart.sh
```

This will take several minutes as 3 local kind clusters are started and configured in a hub and spoke architecture.

### Verify the Gateway and configuration

View the ManagedZone, Gateway and TLSPolicy. The ManagedZone and TLSPolicy should have a Ready status of true. The Gateway should have a Programmed status of True.

```bash
kubectl --context kind-api-control-plane get managedzone,tlspolicy,gateway -n multi-cluster-gateways
```

### Guard Rails: Constraint warnings about missing policies ( DNS, TLS)

Running the quick start script above will bring up [Gatekeeper](https://open-policy-agent.github.io/gatekeeper/website/docs) and the following constraints: 

* Gateways must have a TLSPolicy targeting them
* Gateways must have a DNSPolicy targeting them

To view the above constraints in kubernetes, run this command:
```bash
kubectl --context kind-api-control-plane get constraints
```

**Note:** :exclamation: Since a gateway has been created automatically, along with a TLSPolicy, the violation for a missing DNSPolicy will be active until one is created.

### Grafana dashboard view

To get a top level view of the constraints in violation, the `Stitch: Platform Engineer Dashboard` can be used. This can be accessed by at [https://grafana.172.31.0.2.nip.io](https://grafana.172.31.0.2.nip.io)

Grafana has a default username and password of `admin`.
You can find the `Stitch: Platform Engineer Dashboard` dashboard in the `Default` folder.

### Create the missing DNSPolicy

Create a DNSPolicy that targets the Gateway with the following command:

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

#### Route 53 DNS Zone

When the DNS Policy has been created, a DNS record custom resource will also be created in the cluster resulting in records being created in your AWS Route53. Navigate to Route53 and you should see some new records in the zone. The record will have `petstore` in its name.

### Platform Overview

Since we have created all the policies that Gatekeeper had the guardrails around, you should no longer see any constraints in violation. This can be seen back in the `Stitch: Platform Engineer Dashboard` in Grafana at [https://grafana.172.31.0.2.nip.io](https://grafana.172.31.0.2.nip.io)

## (Application developer) App setup

### API Design

<!-- TODO: Make this repo public somewhere -->

[Fork](https://github.com/Kuadrant/api-poc-petstore/fork) and clone the Petstore App at https://github.com/Kuadrant/api-poc-petstore.

```bash
cd ~
git clone git@github.com:<your_github_username>/api-poc-petstore
```

Then deploy it to the first workload cluster:

```bash
cd ~/api-poc-petstore
kustomize build ./resources/ | envsubst | kubectl --context kind-api-workload-1 apply -f-
```

Configure the app `REGION` to be `eu`:

```bash
kubectl --context kind-api-workload-1 apply -k ./resources/eu-cluster/
```

### Exploring the Open API Specification

The raw Open API spec can be found in the root of the repo:

```bash
cat openapi.yaml
# ---
# openapi: 3.0.2
# info:
#   title: Stitch API Petstore
#   version: 1.0.18
```

Patch the `openapi.yaml` spec file to point at our working, deployed service. This will be used later when trying out the API.

```bash
sed -i '' -e "s|- url: /api/v3|- url: https://petstore.$KUADRANT_ZONE_ROOT_DOMAIN/api/v3/|" openapi.yaml
```

<!--TODO also result in a file called openapi.yaml'' on mac -->

## (Application developer) API security

We've included a number of sample `x-kuadrant` extensions in the OAS spec already:

- At the top-level of our spec, we've defined an `x-kuadrant` extension to detail the Gateway API Gateway associated with our app:

```yaml
  x-kuadrant:
    route:
      name: petstore
      namespace: petstore
      labels:
        deployment: petstore
        owner: cferreir
      hostnames:
      - petstore.$KUADRANT_ZONE_ROOT_DOMAIN
      parentRefs:
      - name: prod-web
        namespace: kuadrant-multi-cluster-gateways
        kind: Gateway
```

- In `/user/login`, we have a Gateway API `backendRef` set and a `rate_limit` set. The rate limit policy for this endpoint restricts usage of this endpoint to 2 requests in a 10 second window:
    ```yaml
    x-kuadrant:
      backendRefs:
      - name: petstore
        namespace: petstore
        port: 8080
      rate_limit:
      rates:
      - limit: 2
        duration: 10
        unit: second
    ```
- In `/store/inventory`, we have also have a Gateway API `backendRef`set and a `rate_limit` set. The rate limit policy for the endpoint restricts usage of this endpoint to 10 requests in a 10 second window:
    ```yaml
    x-kuadrant:
      backendRefs:
      - name: petstore
        namespace: petstore
        port: 8080
      rate_limit:
        rates:
        - limit: 10
          duration: 10
          unit: second
    ```
- Finally, we have a `securityScheme` setup for apiKey auth, powered by Authorino. We'll show this in more detail a little later:
  ```yaml
  securitySchemes:
    api_key:
      type: apiKey
      name: api_key
      in: header
  ```

These extensions allow us to automatically generate Kuadrant Kubernetes resources, including [AuthPolicies](https://docs.kuadrant.io/kuadrant-operator/doc/auth/), [RateLimitPolicies](https://docs.kuadrant.io/kuadrant-operator/doc/rate-limiting/) and [Gateway API resources](https://gateway-api.sigs.k8s.io/reference/spec/) such as HTTPRoutes.

### kuadrantctl

`kuadrantctl` is a cli that supports the generation of various Kubernetes resources via OAS specs. Let's run some commands to generate some of these resources, check these into your forked repo, and apply these to our running workload to implement rate limiting and auth.

### Installing `kuadrantctl`
Download `kuadrantctl` from the `v0.2.0` release artifacts:

https://github.com/Kuadrant/kuadrantctl/releases/tag/v0.2.0

Drop the `kuadrantctl` binary somewhere into your $PATH (e.g. `/usr/local/bin/`).

For this next part of the tutorial, we recommend installing [`yq`](https://github.com/mikefarah/yq) to pretty-print YAML resources.

### Generating Kuadrant resources with `kuadrantctl`

In your fork of the petstore app, we'll generate an `AuthPolicy` to implement API key auth, per the `securityScheme` in our OAS spec:

```bash
# Show the generated AuthPolicy
kuadrantctl generate kuadrant authpolicy --oas openapi.yaml | yq -P

# Generate this resource and save:
kuadrantctl generate kuadrant authpolicy --oas openapi.yaml | yq -P > resources/authpolicy.yaml

# Apply this resource to our cluster:
kubectl --context kind-api-workload-1 apply -f ./resources/authpolicy.yaml

# Push this change back to your fork
git add resources/authpolicy.yaml
git commit -am "Generated AuthPolicy"
git push # You may need to set an upstream as well
```

Next we'll generate a `RateLimitPolicy`, to protect our APIs with the limits we have setup in our OAS spec:

```bash
# Show generated RateLimitPolicy
kuadrantctl generate kuadrant ratelimitpolicy --oas openapi.yaml | yq -P

# Generate this resource and save:
kuadrantctl generate kuadrant ratelimitpolicy --oas openapi.yaml | yq -P > resources/ratelimitpolicy.yaml

# Apply this resource to our cluster:
kubectl --context kind-api-workload-1 apply -f ./resources/ratelimitpolicy.yaml

# Push this change back to your fork
git add resources/ratelimitpolicy.yaml
git commit -am "Generated RateLimitPolicy"
```

Lastly, we'll generate a Gateway API `HTTPRoute` to service our APIs:

```bash
# Show generated HTTPRoute:
kuadrantctl generate gatewayapi httproute --oas openapi.yaml | yq -P

# Generate this resource and save:
kuadrantctl generate gatewayapi httproute --oas openapi.yaml | yq -P > resources/httproute.yaml

# Apply this resource to our cluster, setting the hostname in via the KUADRANT_ZONE_ROOT_DOMAIN env var:
cat ./resources/httproute.yaml | envsubst | kubectl --context kind-api-workload-1 apply -f -

# Push this change back to your fork
git add resources/httproute.yaml
git commit -am "Generated HTTPRoute"
```

### Check our applied policies

Navigate to your app's Swagger UI:

```bash
echo https://petstore.$KUADRANT_ZONE_ROOT_DOMAIN/docs/
```

Let's check that our `RateLimitPolicy` for the `/store/inventory` has been applied and works correctly. Recall, our OAS spec had the following limits applied:

```yaml
x-kuadrant:
  ...
  rate_limit:
    rates:
    - limit: 10
      duration: 10
      unit: second
```
Navigate to the `/store/inventory` API, click `Try it out`, and `Execute`.

You'll see a response similar to:

```json
{
  "available": 10,
  "pending": 5,
  "sold": 3
}
```

This API has a rate limit applied, so if you send more than 10 requests in a 10 second window, you will see a `429` HTTP Status code from responses, and a "Too Many Requests" message in the response body. Click `Execute` quickly in succession to see your `RateLimitPolicy` in action.

### Policy Adjustments

Run the Swagger UI editor to explore the OAS spec and make some tweaks:

```bash
docker run -p 8080:8080 -v $(pwd):/tmp -e SWAGGER_FILE=/tmp/openapi.yaml swaggerapi/swagger-editor

# Navigate to the running Swager Editor
open http://localhost:8080
```

Our `/store/inventory` API needs some additonal rate limiting. This is one of our slowest, most expensive services, so we'd like to rate limit it further.

In your `openapi.yaml`, navigate to the `/store/inventory` endpoint in the `paths` block. Modify the rate_limit block to further restrict the amount of requests this endpoint can serve to 2 requests per 10 seconds:

```yaml
x-kuadrant:
  ...
  rate_limit:
    rates:
    - limit: 2
      duration: 10
      unit: second
```

Save your updated spec - `File` > `Save as YAML` > and update your existing `openapi.yaml`.

Next we'll re-generate our `RateLimitPolicy` with `kuadrantctl`:
```bash
# Show generated RateLimitPolicy
kuadrantctl generate kuadrant ratelimitpolicy --oas openapi.yaml | yq -P

# Generate this resource and save:
kuadrantctl generate gatewayapi ratelimitpolicy --oas openapi.yaml | yq -P > resources/ratelimitpolicy.yaml

# Apply this resource to our cluster:
kubectl --context kind-api-workload-1 apply -f ./resources/ratelimitpolicy.yaml

# Push this change back to your fork
git commit -am "Generated RateLimitPolicy" && git push
```

In your app's Swagger UI:

```bash
echo https://petstore.$KUADRANT_ZONE_ROOT_DOMAIN/docs/
```

Navigate to the `/store/inventory` API one more, click `Try it out`, and `Execute`.

You'll see the effects of our new `RateLimitPolicy` applied. If you now send more than 2 requests in a 10 second window, you'll be rate-limited.

## (Application developer) Scaling the application

Deploy the petstore to the 2nd cluster:

```bash
cd ~/api-poc-petstore
kustomize build ./resources/ | envsubst | kubectl --context kind-api-workload-2 apply -f-
```

Configure the app `REGION` to be `us`:

```bash
kubectl --context kind-api-workload-2 apply -k ./resources/us-cluster/
```

## (Platform engineer) Scaling the gateway and traffic management

Deploy the Gateway to the 2nd cluster:

```bash
kubectl --context kind-api-control-plane patch placement http-gateway --namespace multi-cluster-gateways --type='json' -p='[{"op": "replace", "path": "/spec/numberOfClusters", "value":2}]'
```

Label the 1st cluster as being in the 'EU' region,
and the 2nd cluster as being in the 'US' region.
These labels are used by the DNSPolicy for configuring geo DNS.

```bash
kubectl --context kind-api-control-plane label managedcluster kind-api-workload-1 kuadrant.io/lb-attribute-geo-code=EU --overwrite
kubectl --context kind-api-control-plane label managedcluster kind-api-workload-2 kuadrant.io/lb-attribute-geo-code=US --overwrite
```

## (API consumer) Accessing the API

Show DNS resolution per geo region

TODO

Show rate limiting working on both clusters/apps.

TODO

## (App developer) API traffic monitoring

To view the App developer dashboard, the same Grafana will be used from the platform engineer steps above:
`https://grafana.172.31.0.2.nip.io`

The most relevant for a app developer is `Stitch: App Developer Dashboard`
You should see panels about API's including:

* Request and error rates
* API summaries
* API request summaries
* API duration

All corresponding to our HTTPRoute coming from our OAS spec

## (Platform Engineer) APIs summary view

Now that the app developer has deployed their app, new metrics and data is now available in the platform engineer dashboard seen in the previous step `https://grafana.172.31.0.2.nip.io`:

* Gateways, routes and policies
* Constraints & Violations (there should be no violations present)
* APIs Summary

## Summary

You now have a local environment with a reference architecture to design and deploy an API in a kube native way, using Kuadrant and other open source tools.
