const { Client, KubeConfig } = require('kubernetes-client');
const Request = require('kubernetes-client/backends/request');

// TriggerMesh component definition
const webhookSourceCRD = require('./components/webhooksource-crd.json');
// TriggerMesh component to be created
const webhookSourceCR = require('./components/webhooksource-cr.json');

// Namespace can be customized by setting NAMESPACE environment variable
const namespace = process.env.NAMESPACE || 'default';

async function main() {
    let kubeclient;
    try {
        const kubeconfig = new KubeConfig();

        // Set NODE_ENV to production to use local Pod's
        // certificates for Kubernetes API.
        if (process.env.NODE_ENV === 'production') {
            kubeconfig.loadFromCluster();
        } else {
            kubeconfig.loadFromDefault();
        }

        const backend = new Request({ kubeconfig });

        kubeclient = new Client({ backend });
        await kubeclient.loadSpec();
    } catch (e) {
        console.error(e);
        process.exit();
    }

    kubeclient.addCustomResourceDefinition(webhookSourceCRD);

    // create a WebhookSource object
    try {
        const whs = await kubeclient.apis[webhookSourceCRD.spec.group].v1alpha1.namespaces(namespace).webhooksources.post({ body: webhookSourceCR });
        console.log('Created WebhookSource:', whs);
    } catch (e) {
        console.error(e);
        process.exit();
    }

    console.log("exiting ...")
    process.exit();
}

main();

