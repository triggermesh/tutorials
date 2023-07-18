# Redpanda, TriggerMesh, and Salesforce

## Install Redpanda

### Start minikube

```sh
minikube start
minikube status
```

### Install cert-manager for Redpanda

```sh
helm repo add jetstack https://charts.jetstack.io && \
helm repo update && \
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.12.2 \
  --set installCRDs=true
```

### Install Redpanda operator with Helm

1. To use Helm to add the Redpanda chart repository and update it:

```sh
helm repo add redpanda https://charts.vectorized.io/ && \
helm repo update
```

2. Set the $VERSION environment variable to the latest operator and Redpanda version:

```sh
export VERSION=$(curl -s https://api.github.com/repos/redpanda-data/redpanda/releases/latest | jq -r .tag_name)
```

3. Install the Redpanda operator CRD with bash or zsh:

```sh
noglob kubectl apply \
-k https://github.com/redpanda-data/redpanda/src/go/k8s/config/crd?ref=$VERSION
```

4. Install the Redpanda operator on your Kubernetes cluster:

```sh
helm install \
  redpanda-operator \
  redpanda/redpanda-operator \
  --namespace redpanda-system \
  --create-namespace \
  --version $VERSION
```

### Install a Redpanda cluster

1. Create a namespace for the cluster:

```sh
kubectl create ns redpanda
```

2. Install a single-node cluster (only single-node clusters are supported for local access clusters):

```sh
kubectl apply \
-n redpanda \
-f https://raw.githubusercontent.com/redpanda-data/redpanda/dev/src/go/k8s/config/samples/one_node_cluster.yaml
```

3. Verify that the cluster was created successfully:

```sh
kubectl exec -it -n redpanda one-node-cluster-0 -- rpk cluster metadata --brokers='localhost:9092'
```

### Create topics for the demo

1. Install the `rpk` CLI

```sh
brew install redpanda-data/tap/redpanda
```

2. Run rpk version to display the rpk binary version:

```sh
rpk version
```

3. Create a topic to store salesforce CDC events related to Salesforce Accounts:

```sh
kubectl exec -it -n redpanda one-node-cluster-0 -- rpk topic create salesforce-account-events -p 5 --brokers='localhost:9092'
```

4. List the topics to make sure your :

```sh
kubectl exec -it -n redpanda one-node-cluster-0 -- rpk topic list --brokers='localhost:9092'
```

## Install TriggerMesh

### Install Knative Serving

1. Begin by installing the Knative Operator:

```sh
kubectl apply -f https://github.com/knative/operator/releases/download/knative-v1.8.5/operator.yaml -n default
```

2. Check the status of the Operator by running the command:


```sh
kubectl get deployment knative-operator -n default -w
```

3. Now install the Knative Serving component with the Kourier Networking layer:


```sh
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

4. Check the status of Knative Serving Custom Resource using the command (can take a minute before it displays as ready so we'll use -w to watch the status evolve):

```sh
kubectl get KnativeServing knative-serving -n knative-serving -w
```

Finally configure Knative Serving to use Magic DNS (sslip.io) with:

```sh
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.8.3/serving-default-domain.yaml
```

### Install TriggerMesh using the Helm chart

1. Add the TriggerMesh chart repository to Helm:

```sh
helm repo add triggermesh https://storage.googleapis.com/triggermesh-charts
```

2. Install the chart with the release name triggermesh:

```sh
helm install -n triggermesh triggermesh triggermesh/triggermesh --create-namespace
```

## Setup Salesforce

### Create a Salesforce application

First off, you can now easily create free development accounts in Salesforce to test features like the API for building applications. You can [sign up here](https://developer.salesforce.com/signup).

The TriggerMesh Salesforce source uses [OAuth JWT credentials][salesforce-oauth-jwt] for service authentication. To quote the Salesforce documentation: "This flow uses a certificate to sign the JWT request and doesn’t require explicit user interaction. However, this flow does require prior approval of the client app."

1. First, you will need to generate an X509 certificate for signing and verifying requests.
We will be using `OpenSSL` but any other certificate generation tool should work.

    ```sh
    openssl req -x509 -sha256 -nodes -days 36500 -newkey rsa:2048 -keyout tm-sf.key -out tm-sf.crt
    ```

2. At Salesforce site select `Setup > Apps > App Manager`, click on `New Connected App`.

    ![Setup](assets/1-setup.png)

    ![New Connected App](assets/2-connectedapp.png)

    - Fill in mandatory fields, then click `Enable OAuth Settings`.
    - A callback URL is mandatory but can be filled with any HTTPS data.
    - Enable `Use digital signatures` and upload the public cert (`tm-sf.crt` in the example above).
    - Add Scopes for `api` and `refresh_token, offline_access`.
    - Save

    ![Salesforce connected app](assets/3-configureapp.png)

    - Click on `Manage`.
    - Click `Edit policies`.
    - Set Permitted users to `Admin approved users are pre-authorized`.
    - Save.

    ![Click manage](assets/4-clickmanage.png)

    ![Click edit policies](assets/5-clickeditpolicies.png)

    ![Permitted users](assets/6-permittedusers.png)

    - From further down on the same page, click `Manage Profiles`.
    - Select the profiles that should be allowed to use this application. In our example, when creating a Salesforce developer account, we're assigned the profile `System Administrator`. This is the same user we'll be using to authenticate our TriggerMesh Salesforce source to the Salesforce API. So for now, we'll only add the `System Administrator` profile. 
    - Save

    ![Click manage profiles](assets/7-clickmanageprofiles.png)
    ![Add System Administrator](assets/7bis-addsysadmin.png)
    
3. Retrieve OAuth data to configure TriggerMesh Source.

   - Head back to the list of apps, open the drop-down next to your app and click on `View`.
   - Click on `Manage Consumer Details`. You might need to enter an email verification code in a new window
   - Copy the `Consumer Key` and save it somewhere handy. You won't need the secret because we're using the previously generated certificate to authenticate.  

    ![View app](assets/8-viewapp.png)
    ![Manage consumer details](assets/9-consumerdetails.png)
    ![Enter verification code](assets/10-verificationcode.png)
    ![Copy consumer key](assets/11-copykey.png)

4. Configure the Change Data Capture events that you want to react to

There are a number of different "stream channels" that you can use:

- Change Data Capture events: `/data/ChangeEvents`
- PushTopics for streams based on single entity SOQL queries: `/topic/TicketsSold`
- Standard Platform Events for Salesforce event monitoring: `/event/LoginEventStream`
- Custom Platform Events for your SOQL platform events: `/event/MyCustom__e`

Each Streaming event type has a distinct [set of features][salesroce-event-features]. Please refer to [Salesforce stream API][salesforce-stream-api-docs] on how to create stream channels. 

In this example we're going to use change data capture events to track changes to important sales resources such as accounts, cases, and opportunities.

Head to `Setup > Integrations > Change Data Capture` and enable CDC notifications for the types of objects you're interested in, such as `Account`, `Opportunity`, and `Case`.

![Configure CDC](assets/12-cdc.png)

Your Salesforce app is now configured and you can start ingesting events into TriggerMesh. 

## Ingest Salesforce events into TriggerMesh

If you want, you can create a dedicated namespace for this TriggerMesh integration:

```sh
kubectl create namespace sfdc-to-redpanda
```

We'll start by creating a TriggerMesh Broker that will decouple event producers and consumers and provide a reliable, push-based event delivery pipeline. Create a file called `broker-v1.yaml` with the following content:

```yaml
apiVersion: eventing.triggermesh.io/v1alpha1
kind: RedisBroker
metadata:
  name: triggermesh-redis-broker
  namespace: sfdc-to-redpanda
```

Create the broker:

```sh
kubectl apply -f broker-v1.yaml
```

Now we can create a secret that will contain the Salesforce key we created earlier. Create a file called `salesforce-cert-secret.yaml` and enter the secret's configuration:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: salesforce
  namespace: sfdc-to-redpanda
type: Opaque
stringData:
  certKey: |-
    -----BEGIN PRIVATE KEY-----
    MIIEvAIBADANB
    ...
    6GRQtbkMCfBd7V4GmIXjdg==
    -----END PRIVATE KEY-----
```

Create the secret:

```sh
kubectl apply -f salesforce-cert-secret.yaml
```

And we can also create the salesforce source itself. Use the email address that corresponds to the user name of the account you created on Salesforce developers. Create a file called `salesforce-source-v1.yaml` and save it with the following contents:

```yaml
apiVersion: sources.triggermesh.io/v1alpha1
kind: SalesforceSource
metadata:
  name: salesforce-source
  namespace: sfdc-to-redpanda
spec:
  subscription:
    channel: /data/ChangeEvents
    replayID: -2

  auth:
    clientID: <your consumer key, e.g. 3MVG9OvGYd.....>
    user: <your Salesforce user login email, e.g. bob2@amce.com>
    server: https://login.salesforce.com
    certKey:
      valueFromSecret:
        name: salesforce
        key: certKey
  sink:
    ref:
      apiVersion: eventing.triggermesh.io/v1alpha1
      kind: RedisBroker
      name: triggermesh-redis-broker
```

Create the source:

```sh
kubectl apply -f salesforce-source-v1.yaml
```

To make sure this first ingestion step is working, we'll create an event display service that logs all CloudEvents it receives, and send this service a copy of all events passing through the broker. This pattern is also known as a wiretap.

Create a file called `event-display-wiretap.yaml` with the following contents:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: event-display
  namespace: sfdc-to-redpanda
spec:
  replicas: 1
  selector:
    matchLabels: &labels
      app: event-display
  template:
    metadata:
      labels: *labels
    spec:
      containers:
        - name: event-display
          image: gcr.io/knative-releases/knative.dev/eventing/cmd/event_display

---

kind: Service
apiVersion: v1
metadata:
  name: event-display
  namespace: sfdc-to-redpanda
spec:
  selector:
    app: event-display
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080

---

apiVersion: eventing.triggermesh.io/v1alpha1
kind: Trigger
metadata:
  name: event-display-trigger
  namespace: sfdc-to-redpanda
spec:
  broker:
    group: eventing.triggermesh.io
    kind: RedisBroker
    name: triggermesh-redis-broker
  target:
    ref:
      apiVersion: v1
      kind: Service
      name: event-display
```

Create the wiretap:

```sh
kubectl apply -f event-display-wiretap.yaml
```

In a new window, watch the logs from the event display service:

```sh
kubectl get pods
NAME                                                  READY   STATUS    RESTARTS   AGE
event-display-6994b6cc4c-fvq8w                        1/1     Running   0          30s
salesforcesource-salesforce-source-847ff57bd8-ghsfk   1/1     Running   0          12m
triggermesh-redis-broker-rb-broker-74ff75d48d-rsbfc   1/1     Running   0          26m
triggermesh-redis-broker-rb-redis-778b9c8fb4-lhskm    1/1     Running   0          27m
```

```sh
kubectl logs -f event-display-6994b6cc4c-fvq8w
```

Create a new account in Salesforce, and you should see a new change event appear in the event display logs. 

To do this, first head to the accounts page, for example by first heading to `View all` then selecting `Accounts`:

![View all](assets/13-viewall.png)

![Accounts](assets/14-accounts.png)

Then create a new account, for example with the name `Redpanda`:

![New account](assets/15-new.png)

![New Redpanda account](assets/16-redpanda.png)

Save the new account, and then check your event display logs. You should see a new change event indicating that a new `Account` named `Redpanda` was created:

```sh
☁️  cloudevents.Event
Context Attributes,
  specversion: 1.0
  type: com.salesforce.stream.message
  source: salesforce-source/data/ChangeEvents
  subject: Account/CREATE
  id: 192ff6d1-e15f-4767-89da-c9644eec8f5c
  time: 2023-07-18T14:15:27.532305888Z
  datacontenttype: application/json
Data,
  {
    "event": {
      "createdDate": "0001-01-01T00:00:00Z",
      "replayId": 31641490
    },
    "schema": "JPyUm_b7b4SSjXobT5DOPg",
    "payload": {
      "LastModifiedDate": "2023-07-18T14:15:24.000Z",
      "Name": "Redpanda",
      "OwnerId": "0050600000H0tB5AAJ",
      "CreatedById": "0050600000H0tB5AAJ",
      "CleanStatus": "Pending",
      "ChangeEventHeader": {
        "commitNumber": 11696120723556,
        "commitUser": "0050600000H0tB5AAJ",
        "sequenceNumber": 1,
        "entityName": "Account",
        "changeType": "CREATE",
        "changedFields": [],
        "changeOrigin": "com/salesforce/api/soap/58.0;client=SfdcInternalAPI/",
        "transactionKey": "0000d388-e8a0-4796-9944-732b3a99a31d",
        "commitTimestamp": 1689689724000,
        "recordIds": [
          "00106000029G61DAAS"
        ]
      },
      "CreatedDate": "2023-07-18T14:15:24.000Z",
      "LastModifiedById": "0050600000H0tB5AAJ"
    }
  }
```

You'll notice that this Salesforce CDC event is wrapped into a CloudEvent, which is the native event envelope used by TriggerMesh. It includes `Context Attributes` that can be useful for routing events.

If we now update this account, for example by updating the account's Rating to `Hot`, we'll see an update notification: 

```sh
☁️  cloudevents.Event
Context Attributes,
  specversion: 1.0
  type: com.salesforce.stream.message
  source: salesforce-source/data/ChangeEvents
  subject: Account/UPDATE
  id: 6833266d-417a-49c4-b40e-d76676f5d5d1
  time: 2023-07-18T14:46:51.150001926Z
  datacontenttype: application/json
Data,
  {
    "event": {
      "createdDate": "0001-01-01T00:00:00Z",
      "replayId": 31641494
    },
    "schema": "JPyUm_b7b4SSjXobT5DOPg",
    "payload": {
      "LastModifiedDate": "2023-07-18T14:46:50.000Z",
      "Rating": "Hot",
      "ChangeEventHeader": {
        "commitNumber": 11696145023574,
        "commitUser": "0050600000H0tB5AAJ",
        "sequenceNumber": 1,
        "entityName": "Account",
        "changeType": "UPDATE",
        "changedFields": [
          "Rating",
          "LastModifiedDate"
        ],
        "changeOrigin": "com/salesforce/api/soap/58.0;client=SfdcInternalAPI/",
        "transactionKey": "000171b6-1688-feb9-f59e-bb0dbfe74dbc",
        "commitTimestamp": 1689691610000,
        "recordIds": [
          "00106000029G61DAAS"
        ]
      }
    }
  }
```

## Add a transformation

TODO

## Push Salesforce events to Redpanda

Now we'll create a TriggerMesh Kafka target that will push events into a Redpanda topic.

You'll need to find your broker's bootstrap URL, which you can do with the following command:

```sh
kubectl -n redpanda exec -ti one-node-cluster-0 -c redpanda -- rpk cluster info --brokers='localhost:9092'
CLUSTER
=======
redpanda.93c56865-43ca-4102-bc50-9562bed6c074

BROKERS
=======
ID    HOST                                                             PORT
0*    one-node-cluster-0.one-node-cluster.redpanda.svc.cluster.local.  9092

TOPICS
======
NAME               PARTITIONS  REPLICAS
salesforce-events  5           1

```

Create a file called `kafka-target-v1.yaml`. We'll include both the target definition itself, as well as a new Trigger that will route change events related to Saleforce Accounts from the TriggerMesh Broker to this target. 

Create a file called  with the following contents, which includes your previously fetched broker hostname and port:

```yaml
apiVersion: targets.triggermesh.io/v1alpha1
kind: KafkaTarget
metadata:
  name: kafka-target
  namespace: sfdc-to-redpanda
spec:
  bootstrapServers:
    - one-node-cluster-0.one-node-cluster.redpanda.svc.cluster.local:9092
  topic: salesforce-account-events
  discardCloudEventContext: true

---

apiVersion: eventing.triggermesh.io/v1alpha1
kind: Trigger
metadata:
  name: saleforce-events-trigger
  namespace: sfdc-to-redpanda
spec:
  broker:
    group: eventing.triggermesh.io
    kind: RedisBroker
    name: triggermesh-redis-broker
  target:
    ref:
      apiVersion: targets.triggermesh.io/v1alpha1
      kind: KafkaTarget
      name: kafka-target
  filters:
  - prefix:
      subject: Account
```

As you can see above, the Trigger includes a filter which will match events whose "subject" metadata starts with the value `Account`. 

Create the Target and Trigger:

```sh
kubectl apply -f kafka-target-v1.yaml
```

Now make another change to the Account in Saleforce, and the event should first show up in the Event Display logs, and also in the Redpanda topic called `salesforce-account-events`. 

I'm going to set the account's "Website" to `https://redpanda.com/`.

You can check that the event was written to the topic like so:

```sh
kubectl exec -it -n redpanda one-node-cluster-0 -- rpk topic consume salesforce-account-events --format json --brokers='localhost:9092'
Defaulted container "redpanda" out of: redpanda, redpanda-configurator (init)
{
  "topic": "salesforce-account-events",
  "key": "936428b2-67e2-46c4-9494-fc51fd6b1607",
  "value": "{\"event\":{\"createdDate\":\"0001-01-01T00:00:00Z\",\"replayId\":31641503},\"schema\":\"JPyUm_b7b4SSjXobT5DOPg\",\"payload\":{\"LastModifiedDate\":\"2023-07-18T15:09:57.000Z\",\"Website\":\"https://redpanda.com/\",\"ChangeEventHeader\":{\"commitNumber\":11696163387844,\"commitUser\":\"0050600000H0tB5AAJ\",\"sequenceNumber\":1,\"entityName\":\"Account\",\"changeType\":\"UPDATE\",\"changedFields\":[\"Website\",\"LastModifiedDate\"],\"changeOrigin\":\"com/salesforce/api/soap/58.0;client=SfdcInternalAPI/\",\"transactionKey\":\"000172f8-febd-baf6-777c-17877d27468d\",\"commitTimestamp\":1689692997000,\"recordIds\":[\"00106000029G61DAAS\"]}}}",
  "timestamp": 1689693000673,
  "partition": 4,
  "offset": 0
}
```

## Push events from Redpanda back into Salesforce

## Monitor

[salesforce-stream-api-docs]: https://developer.salesforce.com/docs/atlas.en-us.api_streaming.meta/api_streaming/
[salesforce-oauth-jwt]: https://help.salesforce.com/articleView?id=remoteaccess_oauth_jwt_flow.htm
[salesroce-event-features]: https://developer.salesforce.com/docs/atlas.en-us.api_streaming.meta/api_streaming/event_comparison.htm
[ce]: https://cloudevents.io/