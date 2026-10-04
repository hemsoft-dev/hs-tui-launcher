// This preload runs inside each mutation test process, not the npm installer.
// The Jev tests inject auth and fetch doubles. Any accidental real I/O fails.
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import tls from 'node:tls';
import dgram from 'node:dgram';
import dns from 'node:dns';
import dnsPromises from 'node:dns/promises';
import { syncBuiltinESMExports } from 'node:module';

const denyNetwork = () => {
  throw new Error('Mutation tests must not access the network.');
};
globalThis.fetch = denyNetwork;
http.request = http.get = denyNetwork;
https.request = https.get = denyNetwork;
net.connect = net.createConnection = denyNetwork;
net.Socket.prototype.connect = denyNetwork;
tls.connect = denyNetwork;
dgram.createSocket = denyNetwork;
for (const api of [dns, dnsPromises, dns.Resolver.prototype, dnsPromises.Resolver.prototype]) {
  for (const name of Object.getOwnPropertyNames(api)) {
    if (/^(lookup|resolve|reverse)/.test(name) && typeof api[name] === 'function') {
      api[name] = denyNetwork;
    }
  }
}
syncBuiltinESMExports();
