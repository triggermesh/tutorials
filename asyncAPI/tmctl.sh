tmctl create broker TriggerMeshAsyncAPI
tmctl create source kafka --name orders-kafkasource --topic orders --bootstrapServers host.docker.internal:9092 --groupID orders-group
tmctl create source httppoller --name orderjson-httppollersource --method GET --endpoint http://host.docker.internal:8000/order.json --interval 10s --eventType io.triggermesh.httppoller.event
tmctl create source googlecloudpubsub --name orders-gcp-pubsubsource --topic projects/jmcx-asyncapi/topics/ordersgcp --serviceAccountKey $(cat serviceaccountkey.json)
