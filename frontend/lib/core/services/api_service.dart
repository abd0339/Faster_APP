import 'package:dio/dio.dart';
import '../constants/api_constants.dart';
import 'storage_service.dart';

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  late final Dio _dio;
  bool _initialized = false;

  // ─── Initialize once ──────────────────────────────
  Future<void> init() async {
    if (_initialized) return;

    _dio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Access-Control-Allow-Origin': '*',
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
          // 401 = token expired → trigger logout
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

  // ─── Upload image (multipart) ─────────────────────
  Future<Response> uploadImage(
    String path,
    String filePath,
    String fieldName,
  ) async {
    await init();
    final formData = FormData.fromMap({
      fieldName: await MultipartFile.fromFile(
        filePath,
        filename: filePath.split('/').last,
      ),
    });
    return _dio.post(path, data: formData);
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
