// This preload runs inside each mutation test process, not the npm installer.
// The Jev tests inject auth and fetch doubles. Any accidental real I/O fails.
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import tls from 'node:tls';
import dgram from 'node:dgram';
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
syncBuiltinESMExports();
