import test from 'node:test';
import assert from 'node:assert/strict';
import { request as httpRequest } from 'node:http';
import { get as httpsGet } from 'node:https';
import { connect, Socket } from 'node:net';
import { connect as tlsConnect } from 'node:tls';
import { createSocket } from 'node:dgram';
import dns, { lookup, resolve4, reverse } from 'node:dns';
import dnsPromises, { resolve as resolvePromise } from 'node:dns/promises';

test('mutation test preload rejects real network APIs before connecting', () => {
  for (const operation of [
    () => fetch('https://example.test'),
    () => httpRequest('http://example.test'),
    () => httpsGet('https://example.test'),
    () => connect(443, 'example.test'),
    () => new Socket().connect(443, 'example.test'),
    () => tlsConnect(443, 'example.test'),
    () => createSocket('udp4'),
    () => lookup('example.test', () => {}),
    () => resolve4('example.test', () => {}),
    () => reverse('192.0.2.1', () => {}),
    () => resolvePromise('example.test'),
    () => new dns.Resolver().resolveTxt('example.test', () => {}),
    () => new dnsPromises.Resolver().reverse('192.0.2.1'),
  ]) {
    assert.throws(operation, /Mutation tests must not access the network\./);
  }
});
