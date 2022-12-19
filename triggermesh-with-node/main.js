const { Client, KubeConfig } = require('kubernetes-client');
const Request = require('kubernetes-client/backends/request');

// TriggerMesh component definition
const httppollerSourceCRD = require('./components/httppollersource-crd.json');
// TriggerMesh component to be created
const httppollerSourceCR = require('./components/httppollersource-cr.json');

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

    kubeclient.addCustomResourceDefinition(httppollerSourceCRD);

    // create an HTTPPollerSource object
    try {
        const whs = await kubeclient.apis[httppollerSourceCRD.spec.group].v1alpha1.namespaces(namespace).httppollersources.post({ body: httppollerSourceCR });
        console.log('Created HTTPPollerSource:', whs);

        // HINT: do you want to delete the HTTPPollerSource? ... use this code:
        // const whs = await kubeclient.apis[httppollerSourceCRD.spec.group].v1alpha1.namespaces(namespace).httppollersources('ws-with-node').delete();
        // console.log('Deleted HTTPPollerSource:', whs);
    } catch (e) {
        console.error(e);
        process.exit();
    }

    console.log("exiting ...")
    process.exit();
}

main();

