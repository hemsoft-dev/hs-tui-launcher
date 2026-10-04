import test from 'node:test';
import assert from 'node:assert/strict';
import { request as httpRequest } from 'node:http';
import { get as httpsGet } from 'node:https';
import { connect, Socket } from 'node:net';
import { connect as tlsConnect } from 'node:tls';
import { createSocket } from 'node:dgram';

test('mutation test preload rejects real network APIs before connecting', () => {
  for (const operation of [
    () => fetch('https://example.test'),
    () => httpRequest('http://example.test'),
    () => httpsGet('https://example.test'),
    () => connect(443, 'example.test'),
    () => new Socket().connect(443, 'example.test'),
    () => tlsConnect(443, 'example.test'),
    () => createSocket('udp4'),
  ]) {
    assert.throws(operation, /Mutation tests must not access the network\./);
  }
});
