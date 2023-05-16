# Use Microcks to automatically mock and test TriggerMesh event flows

Start Microcks on M1, in dev mode, with async features (using Redpanda):

```sh
git clone https://github.com/microcks/microcks.git
cd microcks/install/docker-compose
docker compose -f docker-compose-devmode-osx-m1.yml up -d
```

For other docker-compose options, see [here](https://microcks.io/documentation/installing/docker-compose/).

Open the Microcks GUI at `http://localhost:8080/`.

Click on `Importers` in the left menu and create a new Importer. We'll use this to import the AsyncAPI file that defines the mock events and payload schemas that Microcks should use for testing.

Import the provided AsyncAPI file: **TO FIX WHEN MERGED**

```
https://raw.githubusercontent.com/triggermesh/tutorials/microcks-mocks-and-tests/microcks-mocks-and-tests/asyncapi.yaml
```

