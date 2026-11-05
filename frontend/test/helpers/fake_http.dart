import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Minimal fake [HttpHeaders] backing the fake responses below. Only ever
/// asked for `content-type` by the code under test; every other member is a
/// no-op via [noSuchMethod].
class FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _entries = {
    'content-type': ['application/json'],
  };

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _entries.forEach(action);
  }

  @override
  List<String>? operator [](String name) => _entries[name];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Fake [HttpClientResponse] that successfully yields [body] as its one
/// chunk, with a 200 status.
class FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  FakeHttpClientResponse(String body) : _bytes = utf8.encode(body);

  final List<int> _bytes;

  @override
  int get statusCode => 200;

  @override
  String get reasonPhrase => 'OK';

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  HttpHeaders get headers => FakeHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Fake [HttpClientRequest] whose [close] immediately resolves with
/// [_response] — nothing inspects the request side (headers written,
/// body written, etc.) in these tests.
class FakeHttpClientRequest implements HttpClientRequest {
  FakeHttpClientRequest(this._response);

  final HttpClientResponse _response;

  @override
  HttpHeaders get headers => FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _response;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A fake [HttpClient] that delegates every `openUrl` call to [handler], so
/// each test file can route requests by path however the screen under test
/// needs (which endpoints succeed/fail, and with what body) without
/// duplicating the [HttpClient] plumbing itself.
///
/// This has to be a single client installed once via [HttpOverrides.global]
/// (in a `setUpAll`) rather than a fresh one per test: Dio's IO adapter
/// creates its underlying [HttpClient] lazily and caches it for the
/// lifetime of `ApiService`'s singleton Dio instance, so only the override
/// in place the *first* time any test in a file makes a request would ever
/// take effect if each test tried installing its own.
class RoutingHttpClient implements HttpClient {
  RoutingHttpClient(this.handler);

  final Future<HttpClientRequest> Function(Uri url) handler;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => handler(url);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// [HttpOverrides] that always hands out [client] as the app's one and only
/// [HttpClient], so widget tests can fake out Dio's IO adapter instead of
/// letting it hit the real network (and hang).
class TestHttpOverrides extends HttpOverrides {
  TestHttpOverrides(this.client);

  final HttpClient client;

  @override
  HttpClient createHttpClient(SecurityContext? context) => client;
}
