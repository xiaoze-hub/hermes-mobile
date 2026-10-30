import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_mobile/services/hermes_gateway_service.dart';

void main() {
  late HttpServer server;
  late HermesGatewayService service;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    service = HermesGatewayService(
        serverUrl: 'http://127.0.0.1:${server.port}', token: '');
  });

  tearDown(() async {
    service.dispose();
    await server.close(force: true);
  });

  test('reads wrapped history and requests the latest page', () async {
    final requestDone = Completer<void>();
    server.listen((request) async {
      expect(request.uri.path, '/api/sessions/session-1/messages');
      expect(request.uri.queryParameters['order'], 'latest');
      expect(request.uri.queryParameters['limit'], '100');
      expect(request.uri.queryParameters['offset'], '0');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'session_id': 'session-1',
        'messages': [
          {'role': 'user', 'content': 'hello'}
        ]
      }));
      await request.response.close();
      requestDone.complete();
    });
    final messages = await service.getSessionMessages('session-1');
    await requestDone.future;
    expect(messages.single['content'], 'hello');
  });

  test('rejects an unrecognised history response', () async {
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'unexpected': []}));
      await request.response.close();
    });
    await expectLater(
        service.getSessionMessages('session-1'), throwsFormatException);
  });

  test('resumes and submits using JSON-RPC when gateway announces it',
      () async {
    final resumed = Completer<Map<String, dynamic>>();
    final submitted = Completer<Map<String, dynamic>>();
    final snapshot = service.streamEvents
        .firstWhere((event) => event['type'] == 'resume_snapshot');
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {'type': 'gateway.ready', 'payload': {}}
      }));
      socket.listen((data) {
        final frame = jsonDecode(data as String) as Map<String, dynamic>;
        if (frame['method'] == 'session.resume') {
          resumed.complete(frame);
          socket.add(jsonEncode({
            'jsonrpc': '2.0',
            'id': frame['id'],
            'result': {
              'running': true,
              'inflight': {'assistant': 'in progress'}
            }
          }));
        }
        if (frame['method'] == 'prompt.submit') submitted.complete(frame);
        if (frame['method'] == 'session.create') {
          socket.add(jsonEncode({
            'jsonrpc': '2.0',
            'id': frame['id'],
            'result': {'session_id': 'created'}
          }));
        }
      });
    });
    await service.connectWebSocket('session-1');
    expect(
        (await resumed.future.timeout(const Duration(seconds: 5)))['params']
            ['session_id'],
        'session-1');
    expect(
        (await snapshot.timeout(const Duration(seconds: 5)))['inflight']
            ['assistant'],
        'in progress');
    final created = await service.createSession(title: 'new');
    expect(created.id, 'created');
    service.sendMessage(sessionId: 'session-1', text: 'hello');
    expect(
        (await submitted.future.timeout(const Duration(seconds: 5)))['params']
            ['text'],
        'hello');
  });
  test('creates a first session through the JSON-RPC gateway', () async {
    server.listen((request) async {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = 405;
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {'type': 'gateway.ready', 'payload': {}}
      }));
      socket.listen((data) {
        final frame = jsonDecode(data as String) as Map<String, dynamic>;
        if (frame['method'] == 'session.create') {
          socket.add(jsonEncode({
            'jsonrpc': '2.0',
            'id': frame['id'],
            'result': {'session_id': 'first'}
          }));
        }
      });
    });
    final created = await service.createSession(title: 'first');
    expect(created.id, 'first');
  });
}
