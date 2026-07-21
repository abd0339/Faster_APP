import 'package:dio/dio.dart';
import 'dart:typed_data';
import '../constants/api_constants.dart';
import '../constants/app_config.dart';
import 'storage_service.dart';

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  late final Dio _dio;
  bool _initialized = false;

  // ─── Initialize once on app start ─────────────────
  // Uses AppConfig.backendUrl which reads from .env
  // Falls back to localhost:8080 if .env not loaded
  Future<void> init() async {
    if (_initialized) return;

    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.backendUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    // ─── Add auth token to every request ──────────
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await StorageService.instance.getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          // 401 = token expired → clear session
          if (error.response?.statusCode == 401) {
            StorageService.instance.clearAll();
          }
          handler.next(error);
        },
      ),
    );

    _initialized = true;
  }

  // ─── GET ──────────────────────────────────────────
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParams,
  }) async {
    await init();
    return _dio.get(path, queryParameters: queryParams);
  }

  // ─── POST ─────────────────────────────────────────
  Future<Response> post(
    String path, {
    dynamic data,
  }) async {
    await init();
    return _dio.post(path, data: data);
  }

  // ─── PUT ──────────────────────────────────────────
  Future<Response> put(
    String path, {
    dynamic data,
  }) async {
    await init();
    return _dio.put(path, data: data);
  }

  // ─── PATCH ────────────────────────────────────────
  Future<Response> patch(
    String path, {
    dynamic data,
  }) async {
    await init();
    return _dio.patch(path, data: data);
  }

  // ─── DELETE ───────────────────────────────────────
  Future<Response> delete(String path) async {
    await init();
    return _dio.delete(path);
  }

  // ─── GET raw bytes (authenticated image fetch) ────
  // NEW — needed for driver documents and other private
  // images. Image.network() can't attach the JWT auth
  // header, so the admin/driver document viewers fetch
  // bytes through Dio (which already has the interceptor)
  // and render them with Image.memory() instead.
  Future<Uint8List> getBytes(String path) async {
    await init();
    final response = await _dio.get<List<int>>(
      path,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? []);
  }

  // ─── Upload image (multipart — web + mobile) ──────
  Future<Response> uploadImageBytes(
    String path,
    Uint8List bytes,
    String filename,
    String fieldName,
  ) async {
    await init();
    final formData = FormData.fromMap({
      fieldName: MultipartFile.fromBytes(
        bytes,
        filename: filename,
      ),
    });
    return _dio.post(
      path,
      data: formData,
      options: Options(
        headers: {'Content-Type': 'multipart/form-data'},
      ),
    );
  }

  // ─── Error message helper ─────────────────────────
  static String getErrorMessage(dynamic error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
          return 'Connection timeout. Check your internet.';
        case DioExceptionType.receiveTimeout:
          return 'Server is taking too long to respond.';
        case DioExceptionType.connectionError:
          return 'Cannot connect to server. Is the backend running?';
        default:
          return 'Something went wrong. Please try again.';
      }
    }
    return error.toString();
  }
}
