import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rendel/rendel.dart';
import 'package:rendel/src/transport/api_client.dart';

/// A file the person attached, handed to the app's own action.
///
/// Blushy, 26 November: the person attached a photo and asked for it to be
/// shared; the action could not have it, opened the gallery, and the person
/// had to pick it again. `RendelSchema.file` declares the parameter; the
/// handler gets the attachment's id and `Rendel.attachment` the bytes.
void main() {
  test('RendelSchema.file declares an attachment the server checks and the card shows', () {
    expect(RendelSchema.file(description: 'The outfit photo.', title: 'Fotoğraf').toJson(), {
      'type': 'string',
      'format': 'attachment',
      'description': 'The outfit photo.',
      'title': 'Fotoğraf',
    });
    final schema = RendelSchema.object({'photo': RendelSchema.file().optional}).toJson();
    expect(schema['required'], isNull);
  });

  group('RendelApiClient.attachment', () {
    final photo = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2]);

    test('gives a file this run uploaded without asking the server', () async {
      final asked = <String>[];
      final api = RendelApiClient(
        appKey: 'rd_pk_test_x',
        deviceId: 'd1',
        config: const RendelConfig(),
        httpClient: MockClient((request) async {
          asked.add('${request.method} ${request.url.path}');
          return http.Response('{"id":"11111111-1111-4111-8111-111111111111","media_type":"image/jpeg","bytes":6}', 201);
        }),
      );
      final id = await api.upload(photo, 'image/jpeg', fileName: 'look.jpg');
      final file = await api.attachment(id);
      expect(file!.bytes, photo);
      expect(file.name, 'look.jpg');
      expect(file.mediaType, 'image/jpeg');
      expect(asked, ['POST /v1/uploads']);
    });

    test("reads one it does not hold from the server, as this device, and null where there is none", () async {
      final asked = <http.Request>[];
      final api = RendelApiClient(
        appKey: 'rd_pk_test_x',
        deviceId: 'd1',
        config: const RendelConfig(),
        httpClient: MockClient((request) async {
          asked.add(request);
          if (request.url.path.endsWith('/22222222-2222-4222-8222-222222222222')) {
            return http.Response.bytes(photo, 200, headers: {'content-type': 'image/jpeg', 'x-rendel-filename': 'Ayna%20ayna.jpg'});
          }
          return http.Response('{"error":{"code":"not_found"}}', 404);
        }),
      );
      final file = await api.attachment('22222222-2222-4222-8222-222222222222');
      expect(file!.bytes, photo);
      expect(file.name, 'Ayna ayna.jpg');
      expect(asked.single.method, 'GET');
      expect(asked.single.headers['X-Rendel-Device'], 'd1');
      expect(asked.single.headers['X-Rendel-Key'], 'rd_pk_test_x');
      expect(await api.attachment('33333333-3333-4333-8333-333333333333'), isNull);
    });
  });

  test('Rendel.attachment is null when nobody attached one', () async {
    expect(await Rendel.attachment(null), isNull);
    expect(await Rendel.attachment(' '), isNull);
  });
}
