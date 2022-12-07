# TriggerMesh with node.js

In this tutorial we are going to programatically create a `WebhookSource` that is able to send events to an HTTP sink.
For demoing purposes we are going to require [TriggerMesh stack](https://docs.triggermesh.io/installation/kubernetes-yaml/) deployed at the Kubernetes cluster. This enable us to use `WebhookSource` and our Brokers.

![coded-webhook](assets/coded-webhooksource.png)

## DevOps Tasks

Create a namespace for this tutorial:

```console
kubectl create ns tm-nodejs
```

Create a Broker, a target service that consumes events, and a trigger that does the subscription between both:

```console
# Create RedisBroker
kubectl apply -n tm-nodejs -f https://raw.githubusercontent.com/triggermesh/triggermesh-core/main/docs/assets/manifests/getting-started-redis/broker.yaml

# Target service (and DLS for non delivered events)
kubectl apply -n tm-nodejs -f https://raw.githubusercontent.com/triggermesh/triggermesh-core/main/docs/assets/manifests/common/display-target.yaml
kubectl apply -n tm-nodejs -f https://raw.githubusercontent.com/triggermesh/triggermesh-core/main/docs/assets/manifests/common/display-deadlettersink.yaml

# Trigger that binds Target and Broker
kubectl apply -n tm-nodejs -f https://raw.githubusercontent.com/triggermesh/triggermesh-core/main/docs/assets/manifests/getting-started-redis/trigger.yaml
```

## Dev Tasks

Kubernetes CRDs must be downloaded and converted to JSON. This can be easily done using the cluster's CRDs in code, but we chose to provide the [JSON for WebhookSource](components/webhooksource-crd.json) to keep the code at minimum.

The [Webhook resource JSON](components/webhooksource-cr.json) is also provided. You can modify it, but keep in mind that the Trigger created will only let event types `demo.type1` through.

### Code It

Setup your project.

```console
npm init
```

Use [GoDaddy's kubernetes library](https://github.com/godaddy/kubernetes-client). Any other Kubernetes library for `node.js` that can has a dynamic client or supports CRDs could be used.

```console
npm i kubernetes-client --save
```

These are the objects required from the Kubernetes library:

```js
const { Client, KubeConfig } = require('kubernetes-client');
const Request = require('kubernetes-client/backends/request');
```

TODO go throught the rest of the code

### Run It

If you are running the application from a Kubernetes Pod, also set `NODE_ENV=production`

```console
NAMESPACE=tm-nodejs node main.js
```

After issuing the command a new webhook should be ready to ingest events from your applications.

```console
kubewclt get webhooksource -n tm-nodejs ws-with-node
NAME           READY   REASON   URL                                                                 SINK                                                AGE
ws-with-node   True             https://webhooksource-ws-with-node-tm-nodejs.piper.triggermesh.io   http://demo-rb-broker.tm-nodejs.svc.cluster.local   78s
```