# Data sources and sinks for Redpanda on Kubernetes with TriggerMesh

## Introduction

Redpanda is a modern Kafka-API compatible data streaming platform, and if you’ve centred your workload orchestration around Kubernetes then you might be inclined to also deploy Redpanda to Kubernetes. Luckily the Redpanda team have you covered and they provide a lot of guidance to help you do this. But if you want an easy way to connect data sources and sinks to Redpanda on Kubernetes the solution might not be as obvious.

Kafka Connect could seem like an obvious choice for data sources and sinks but it was not designed as a Kubernetes-native solution and therefore is not very idiomatic to Kubernetes. There is some interesting reading available [such as this](https://www.morling.dev/blog/ideation-kubernetes-native-kafka-connect/) that discusses some of the challenges of running Kafka Connect on K8s. An alternative to Kafka Connect in this scenario is TriggerMesh, that was built from the ground up to run natively on Kubernetes. It does this by providing Kubernetes controllers and Custom Resource Definitions which means to can define source and sinks just like you would any other native Kubernetes object.

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

To start Helm, enter:

`Helm init`

To verify the Tiller server is running properly, use:

`kubectl get pods -n kube-system | grep tiller ``

And the output:

`tiller-deploy-77b79fcbfc-hmqj8 1/1 Running 0 50s`

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

## Setting up TriggerMesh


## (COPIED) Setting up Elasticsearch

It’s time to start deploying the different components of the ELK Stack. Let’s start with Elasticsearch.

As mentioned above, we’ll be using Elastic’s Helm repository so let’s start with adding it:

```sh
helm repo add elastic https://Helm.elastic.co
```

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
