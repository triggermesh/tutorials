## TODO
# generate test data
# use tmctl to send the test data

###############
### PHASE 1 ###
###############

# Gather events and set types

tmctl create broker kafka-pipes

tmctl create source kafka --name orders-source --topic orders --bootstrapServers $(cat config/bootstrap.servers.txt) --groupID mygroup

tmctl create target kafka --name orders-us-groceries-target --topic orders-us-groceries --bootstrapServers $(cat config/bootstrap.servers.txt)
tmctl create target kafka --name orders-us-electronics-target --topic orders-us-electronics --bootstrapServers $(cat config/bootstrap.servers.txt)
tmctl create target kafka --name orders-us-pharma-target --topic orders-us-pharma --bootstrapServers $(cat config/bootstrap.servers.txt)
tmctl create target kafka --name orders-eu-fashion-target --topic orders-eu-fashion --bootstrapServers $(cat config/bootstrap.servers.txt)
tmctl create target kafka --name orders-eu-electronics-target --topic orders-eu-electronics --bootstrapServers $(cat config/bootstrap.servers.txt)
tmctl create target kafka --name orders-eu-books-target --topic orders-eu-books --bootstrapServers $(cat config/bootstrap.servers.txt)

# Now we can send in an order and watch it land in broker

# Next we'll transform
# This makes the type $region-$category-v1.
# v1 so that we can make additional transformations down the road and version each stage.
# Also will let us make transformations before passing the events to their final destinations.

tmctl create transformation --name transform-extract-region-category -f transformations/orders-add-region-category.yaml
tmctl create trigger --eventTypes io.triggermesh.kafka.event --target transform-extract-region-category

# we can now see the tranformed events coming in with a new event type

###############
### PHASE 2 ###
###############

# start sending the events to their destinations

tmctl create trigger --name us-groceries --eventTypes us-groceries-v1 --target orders-us-groceries-target
tmctl create trigger --name us-electronics --eventTypes us-electronics-v1 --target orders-us-electronics-target
tmctl create trigger --name us-pharma --eventTypes us-pharma-v1 --target orders-us-pharma-target
tmctl create trigger --name eu-fashion --eventTypes eu-fashion-v1 --target orders-eu-fashion-target
tmctl create trigger --name eu-electronics --eventTypes eu-electronics-v1 --target orders-eu-electronics-target
tmctl create trigger --name eu-books --eventTypes eu-books-v1 --target orders-eu-books-target

# Now sending the test order will result in a new event in the eu-fashion topic

# we can do a bigger test by sending a big set of events

# bin/kafka-console-producer.sh --broker-list host.docker.internal:9092 --topic orders < example-event-data/1000_generated_mock_events.json
# ../../../tm-projects/kafka_2.13-3.3.1/bin/kafka-console-producer.sh --broker-list localhost:9092,host.docker.internal:9092 --topic orders < example-event-data/1000_generated_mock_events.json

###############
### PHASE 3 ###
###############

# the EU team just reminded us that they want itemid formatted differently
# so we do a transform just on the eu events, and version these types as v2 (done in the transformation)
# a benefit here is that if we want, we can keep people consuming v1 as well

tmctl create transformation --name transform-eu-format -f transformations/orders-eu-format.yaml
tmctl create trigger --eventTypes eu-fashion-v1,eu-electronics-v1,eu-books-v1 --target transform-eu-format

# we need to update the triggers to send v2 events to the eu topics.
# Note that "create" will update the existing triggers
# We're updating all consumers to v2, but we could imagine doing this one by one,
# depending on if people are ready for v2 or not.

tmctl create trigger --name eu-fashion --eventTypes eu-fashion-v2 --target orders-eu-fashion-target
tmctl create trigger --name eu-electronics --eventTypes eu-electronics-v2 --target orders-eu-electronics-target
tmctl create trigger --name eu-books --eventTypes eu-books-v2 --target orders-eu-books-target

# Now we should see EU topics getting the transformed version of the ID

###############
### PHASE 4 ###
###############

# New topic for all electronics orders, irrespective of region, for an analytics team

tmctl create target kafka --name orders-global-electronics-target --topic orders-global-electronics --bootstrapServers $(cat config/bootstrap.servers.txt)
tmctl create trigger --eventTypes eu-electronics-v2,us-electronics-v1 --target orders-global-electronics-target
