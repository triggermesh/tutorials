async function main() {

  const parser = require('@asyncapi/parser');

  const fs = require('fs');

  const outputfile = 'tmctl.sh'

  try {
    data = fs.readFileSync('asyncapi.yaml', 'utf8');
  } catch (err) {
    console.error(err);
  }

  const doc = await parser.parse(data);

  content = "tmctl create broker " + doc.info().title() + "\n";

  console.log(content);

  channels = doc.channels();

  // Iterate over channels
  doc.channelNames().forEach(channel => {
    if (channels[channel].hasSubscribe()){
      if (channels[channel].hasServers()){
        // Iterate over channel servers
        channels[channel].servers().forEach(server => {
          // Create a tmctl command for supported channel/server pairs
          switch (doc.server(server).protocol()) {
            case 'kafka':
              kafkasource(doc.server(channels[channel].servers()[0]),channel);
              break;

            case 'http':
              httpsource(doc.server(channels[channel].servers()[0]),channel);
              break;

            case 'googlepubsub':
              googlepubsubsource(doc.server(channels[channel].servers()[0]),channel);
              break;

            default:
              console.log('Ignored channel/server pair: protocol ' + doc.server(channels[channel].servers()[0]).protocol() + ' not supported.');
              break;
          }
        });
      }
    }
  });

  function kafkasource(server, channel) {
    str = "tmctl create source kafka --name " + channel + "-kafkasource " + "--topic " + channel + " --bootstrapServers " + server.url() + " --groupID " + channel + "-group\n";
    console.log(str);
    content += str;
  }

  function httpsource(server, channel) {
    var regexPattern = /[^A-Za-z0-9]/g;
    var alphanumchannel = channel.replace(regexPattern, "");
    str = "tmctl create source httppoller --name " + alphanumchannel + "-httppollersource " + "--method " + channels[channel].subscribe().bindings().http.method + " --endpoint " + server.url() + channel + " --interval 10s " + "--eventType io.triggermesh.httppoller.event\n";
    console.log(str);
    content += str;
  }

  function googlepubsubsource(server, channel) {
    str = "tmctl create source googlecloudpubsub --name " + channel + "-pubsubsource " + "--topic " + channels[channel].subscribe().bindings().googlepubsub.topic + " --serviceAccountKey $(cat serviceaccountkey.json)\n";
    console.log(str);
    content += str;
  }

  try {
    fs.writeFileSync(outputfile, content);
    // file written successfully
  } catch (err) {
    console.error(err);
  }

}

main()
