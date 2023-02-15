# Data sources and sinks for Redpanda on Kubernetes with TriggerMesh

![image](schema.png)

## Introduction

Redpanda is a modern Kafka-API compatible data streaming platform, and if you’ve centred your workload orchestration around Kubernetes then you might be inclined to also deploy Redpanda to Kubernetes. Luckily the Redpanda team have you covered and they provide a lot of guidance to help you do this. But if you want an easy way to connect data sources and sinks to Redpanda on Kubernetes the solution might not be as obvious.

Kafka Connect could seem like an obvious choice for data sources and sinks but it was not designed as a Kubernetes-native solution and therefore is not very idiomatic to Kubernetes. There is some interesting reading available [such as this](https://www.morling.dev/blog/ideation-kubernetes-native-kafka-connect/) [and this](https://redpanda.com/blog/kafka-kubernetes-deployment-pros-cons) that discuss some of the challenges of running Kafka Connect on K8s. An alternative to Kafka Connect in this scenario is TriggerMesh, that was built from the ground up to run natively on Kubernetes. It does this by providing Kubernetes controllers and Custom Resource Definitions which means to can define source and sinks just like you would any other native Kubernetes object.

In this post we’ll learn the basics of TriggerMesh and discuss how it can be used to get data into and out of Redpanda on Kubernetes. Once both Redpanda and TriggerMesh are installed on Kubernetes, we’ll use the TriggerMesh CLI called tmctl to easily create the K8s manifest for the TriggerMesh connectors.

## (COPIED) What is Elasticsearch?
Enter Elasticsearch, an open source distributed search and analytics engine built on Apache LuceneⓇ. Elasticsearch supports all types of data, including textual, numerical, geospatial, structured, and unstructured data.

Companies like Wikipedia, GitHub, and Facebook use Elasticsearch for use cases such as classic full-text search engine implementation, analytics stores, autocompleters, spellcheckers, alerting engines, and general-purpose document storage.

Elasticsearch becomes even more powerful when it is integrated with a real-time streaming platform like Redpanda. This integration can easily be done by using Kafka ConnectⓇ and compatible connectors like Confluent Elasticsearch Sink ConnectorⓇ or Camel Elasticsearch Sink ConnectorⓇ.

## Scenario

* Your company is in the recruitment business and handles CVs stored on Azure, Google, and AWS object stores
* You don't have a good central view of how many CVs are being manipulated and by who
* You want to ingest file notifications from different clouds, stream them through Redpanda, and push them to Elasticsearch so that you can search for different information regarding CVs being manipulated on the cloud platforms

## (COPIED) Setting up K8s & Helm

Create a multi-node Kubernetes kind cluster:

```sh
kind create cluster --name rp-kind --config kind-config.yaml

kubectl get nodes

#output
NAME                    STATUS   ROLES           AGE   VERSION
rp-kind-control-plane   Ready    control-plane   54s   v1.24.0
rp-kind-worker          Ready    <none>          33s   v1.24.0
rp-kind-worker2         Ready    <none>          34s   v1.24.0
rp-kind-worker3         Ready    <none>          34s   v1.24.0
```

<!-- To start Helm, enter:

`Helm init`

To verify the Tiller server is running properly, use:

`kubectl get pods -n kube-system | grep tiller ``

And the output:

`tiller-deploy-77b79fcbfc-hmqj8 1/1 Running 0 50s` -->

## Setting up Redpanda

Use Helm to spin up a multi-node Redpanda cluster.

```
helm repo add redpanda https://charts.redpanda.com/
helm repo update
helm install redpanda redpanda/redpanda \
    --namespace redpanda \
    --create-namespace
```

It will take a few seconds for the cluster creation. Use this command to track the progress:

```sh
kubectl -n redpanda rollout status statefulset redpanda --watch

#output
Waiting for 3 pods to be ready...
Waiting for 2 pods to be ready...
Waiting for 1 pods to be ready...
statefulset rolling update complete 3 pods at revision redpanda-76d98b7647...
```

## (COPIED) Setting up Elasticsearch

It’s time to start deploying the different components of the ELK Stack. We'll follow the instructions provided by [elastic.co here](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-deploy-eck.html).

### Install the ELK operator

Install custom resource definitions:

```sh
kubectl create -f https://download.elastic.co/downloads/eck/2.6.1/crds.yaml
```

Install the operator with its RBAC rules:

```sh
kubectl apply -f https://download.elastic.co/downloads/eck/2.6.1/operator.yaml
```

Monitor the operator logs:

```sh
kubectl -n elastic-system logs -f statefulset.apps/elastic-operator
```

### Install Elasticsearch

Apply a simple Elasticsearch cluster specification, with one Elasticsearch node:

```sh
cat <<EOF | kubectl apply -f -
apiVersion: elasticsearch.k8s.elastic.co/v1
kind: Elasticsearch
metadata:
  name: quickstart
spec:
  version: 8.6.1
  nodeSets:
  - name: default
    count: 1
    config:
      node.store.allow_mmap: false
EOF
```

The operator automatically creates and manages Kubernetes resources to achieve the desired state of the Elasticsearch cluster. It may take up to a few minutes until all the resources are created and the cluster is ready for use.

Get an overview of the current Elasticsearch clusters in the Kubernetes cluster, including health, version and number of nodes:

```sh
kubectl get elasticsearch

NAME          HEALTH    NODES     VERSION   PHASE         AGE
quickstart    green     1         8.6.1     Ready         1m
```

Now lets request Elasticsearch access. A ClusterIP Service is automatically created for your cluster:

```sh
kubectl get service quickstart-es-http

NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
quickstart-es-http   ClusterIP   10.15.251.145   <none>        9200/TCP   34m
```

Let's get the credentials. A default user named elastic is automatically created with the password stored in a Kubernetes secret:

```sh
PASSWORD=$(kubectl get secret quickstart-es-elastic-user -o go-template='{{.data.elastic | base64decode}}')
```

Let's request the Elasticsearch endpoint. To run a curl request to get this from within the cluster, you can create a curl pod:

```sh
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: curl
  name: curl
spec:
  containers:
  - image: radial/busyboxplus:curl
    imagePullPolicy: IfNotPresent
    name: curl
    stdin: true
    tty: true
EOF
```

Then do:

```
kubectl exec -ti curl -- curl -v -u "elastic:$PASSWORD" -k "https://quickstart-es-http:9200"
```

TO DELETE
kubectl exec -ti curl -- curl -v -u "elastic:$PASSWORD" -k "https://localhost:9200"

From your local workstation, use the following command in a separate terminal:

```
kubectl port-forward service/quickstart-es-http 9200
```

Then request localhost:

```
curl -u "elastic:$PASSWORD" -k "https://localhost:9200"
```

```sh
{
  "name" : "quickstart-es-default-0",
  "cluster_name" : "quickstart",
  "cluster_uuid" : "XqWg0xIiRmmEBg4NMhnYPg",
  "version" : {...},
  "tagline" : "You Know, for Search"
}
```

### Install Kibana

To deploy your Kibana instance go through the following steps.

Specify a Kibana instance and associate it with your Elasticsearch cluster:

```sh
cat <<EOF | kubectl apply -f -
apiVersion: kibana.k8s.elastic.co/v1
kind: Kibana
metadata:
  name: quickstart
spec:
  version: 8.6.1
  count: 1
  elasticsearchRef:
    name: quickstart
EOF
```

Monitor Kibana health and creation progress.

Similar to Elasticsearch, you can retrieve details about Kibana instances:

```sh
kubectl get kibana
```

And the associated Pods:

```sh
kubectl get pod --selector='kibana.k8s.elastic.co/name=quickstart'
```

Access Kibana.

A ClusterIP Service is automatically created for Kibana:

```sh
kubectl get service quickstart-kb-http
```

Use kubectl port-forward to access Kibana from your local workstation:

```sh
kubectl port-forward service/quickstart-kb-http 5601
```

Open https://localhost:5601 in your browser. Your browser will show a warning because the self-signed certificate configured by default is not verified by a known certificate authority and not trusted by your browser. You can temporarily acknowledge the warning for the purposes of this quick start but it is highly recommended that you configure valid certificates for any production deployments.

Login as the elastic user. The password can be obtained with the following command:

```sh
kubectl get secret quickstart-es-elastic-user -o=jsonpath='{.data.elastic}' | base64 --decode; echo
```

## Setting up TriggerMesh on K8s

TriggerMesh relies on Knative Serving to run some of its components as Knative Services. We plan to relax this dependency in the near future. While we recommend following the official installation instructions, the remainder of this section serves as a quick guide for installing the Knative components.

Begin by installing the Knative Operator:

```sh
kubectl apply -f https://github.com/knative/operator/releases/download/knative-v1.8.1/operator.yaml -n default
```

Check the status of the Operator by running the command:

```sh
kubectl get deployment knative-operator -n default
```

Now install the Knative Serving component with the Kourier Networking layer:

```yaml
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: knative-serving
---
apiVersion: operator.knative.dev/v1beta1
kind: KnativeServing
metadata:
  name: knative-serving
  namespace: knative-serving
spec:
  ingress:
    kourier:
      enabled: true
  config:
    network:
      ingress-class: "kourier.ingress.networking.knative.dev"
EOF
```

Check the status of Knative Serving Custom Resource using the command (can take a minute before it displays as ready):

```sh
kubectl get KnativeServing knative-serving -n knative-serving
```

Finally configure Knative Serving to use Magic DNS (sslip.io) with:

```sh
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.8.3/serving-default-domain.yaml
```

Refer to the official documentation if you want to use a real DNS instead.

This concludes the installation of Knative Serving.

Install the TriggerMesh Helm chart
Add the TriggerMesh chart repository to Helm:

```sh
helm repo add triggermesh https://storage.googleapis.com/triggermesh-charts
```

To install the chart with the release name triggermesh:

```sh
helm install -n triggermesh triggermesh triggermesh/triggermesh --create-namespace
```

The command deploys the TriggerMesh open-source components and uses the default configuration that can be adapted depending on your needs.

## Install tmctl, the TriggerMesh CLI

```sh
brew install triggermesh/cli/tmctl
```

Or visit https://docs.triggermesh.io/get-started/quickstart/ for alternatives.

## Send data to Elasticsearch

Lets start by creating a TriggerMesh Elasticsearch target that will send event so Elasticsearch.

First we'll create a broker:

```sh
tmctl create broker triggermesh
```

Then we'll create an Elasticsearch target:

```sh
tutorials/redpanda-triggermesh % tmctl create target elasticsearch --indexName file-notifications --connection config/elasticconnection.yaml
```
curl -u "elastic:$PASSWORD" -k "https://localhost:9200"
```sh
curl -v http://localhost:63236 \
 -X POST \
 -H "Content-Type: application/json" \
 -H "Ce-Specversion: 1.0" \
 -H "Ce-Type: something.to.index.type" \
 -H "Ce-Source: some.origin/instance" \
 -H "Ce-Id: 536808d3-88be-4077-9d7a-a3f162705f79" \
 -d '{"message":"thanks for indexing this message","from": "TriggerMesh targets", "some_number": 12}'
```

## Ingest Amazon S3 events

First setup an Amazon S3 bucket that we'll use as an event source.

You can follow the instructions at [Create your first S3 bucket](https://docs.aws.amazon.com/AmazonS3/latest/userguide/creating-bucket.html).

You'll need the queue's `ARN` and AWS credentials as part of the TriggerMesh command to create the AWS S3 source:

```sh
tmctl create source awss3 --arn <arn> --eventTypes <eventTypes> --auth.credentials.accessKeyID <keyID> --auth.credentials.secretAccessKey <key>
```

## Ingest Azure Blob Storage and Google Cloud Storage events



## (COPIED) Scaling out the consumer application

We started out with a single instance of the consumer application. Increase the number of replicas of the consumer Deployment:

```sh
kubectl scale deployment/redpanda-go-consumer --replicas=2
```

As a result of the scale out, the Redpanda topic partitions will get redistributed among the two instances. Since we created a topic with three partitions, data from two of these partitions will be handled by one instance while the remaining partition data will be taken care of by the second consumer instance.

This should be evident when you inspect the new Pod as well as the previous one to see how partition assignment has changed:

```sh
kubectl get pod -l app=redpanda-go-consumer
kubectl logs -f <name of new pod>

#output (logs)
[sarama] consumer/broker/1 accumulated 1 new subscriptions
[sarama] consumer/broker/1 added subscription to users/1
[sarama] consumer/broker/0 accumulated 1 new subscriptions
[sarama] consumer/broker/0 added subscription to users/2
```

To test this, send some more data to Redpanda.

## (COPIED) Clean up

Once you finish the tutorial, follow these steps to delete the components.

To uninstall the Redpanda Helm release:

```sh
helm uninstall redpanda -n redpanda
```

To delete the kind cluster:

```sh
kind delete clusters rp-kind
```




## TriggerMesh more native to K8s than Kafka Connect

Reproducing a similar example to this one but using Kafka Connect will raise a few questions and pain points:
* Installing Kafka Connect on K8s is not as streamlined as the Helm or YAML approaches supported by TriggerMesh
* Each individual Kafka Connect connector needs to be downloaded and installed manually, whereas TriggerMesh provides them as CRDs
* Configuring the Kafka Connect connectors is done with old-fashioned config files, whereas TriggerMesh is configured with YAML manifests like any other Kubernetes resource
