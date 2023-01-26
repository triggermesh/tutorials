docker-compose up -d

tmctl create broker triggermesh

tmctl create source kafka --name orders-source --topic orders --bootstrapServers $(cat config/bootstrap.servers.txt) --groupID mygroup

tmctl create transformation --name transform-extract-region-category -f transformations/orders-add-region-category.yaml
tmctl create trigger --eventTypes io.triggermesh.kafka.event --target transform-extract-region-category

tmctl create target kafka --name orders-us-books-target --topic orders-us-books --bootstrapServers $(cat config/bootstrap.servers.txt)
tmctl create target kafka --name orders-eu-fashion-target --topic orders-eu-fashion --bootstrapServers $(cat config/bootstrap.servers.txt)

tmctl create trigger --name us-books --eventTypes us-books-v1 --target orders-us-books-target
tmctl create trigger --name eu-fashion --eventTypes eu-fashion-v1 --target orders-eu-fashion-target
