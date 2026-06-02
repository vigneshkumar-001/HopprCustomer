import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide FormData, Response;
import 'package:hopper/Presentation/Authentication/screens/mobile_screens.dart';
import 'package:hopper/Presentation/Drawer/controller/profle_cotroller.dart';
import 'package:hopper/uitls/websocket/socket_io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Request {
  static bool _isHandlingUnauthorized = false;

  static void _debugLogInfo(String message) {
    if (!kDebugMode) return;
    AppLogger.log.i(message);
  }

  static void _debugLogError(String message) {
    if (!kDebugMode) return;
    AppLogger.log.e(message);
  }

  static String _formatBody(dynamic body) {
    if (body == null) return '{}';
    if (body is FormData) {
      final fields = body.fields
          .map((e) => '${e.key}: ${e.value}')
          .toList(growable: false);
      final files = body.files
          .map((e) {
            final f = e.value;
            return '${e.key}: {'
                'filename: ${f.filename}, '
                'length: ${f.length}, '
                'contentType: ${f.contentType}'
                '}';
          })
          .toList(growable: false);
      return 'FormData{fields: $fields, files: $files}';
    }
    return body.toString();
  }

  static void _logRequest({
    required String method,
    required String url,
    required Map<String, dynamic> headers,
    dynamic body,
    Map<String, dynamic>? queryParams,
  }) {
    final authToken = headers['Authorization'];
    final rawToken = authToken?.toString().replaceFirst('Bearer ', '');

    // Debug-only: full request details. Keep production logs clean.
    _debugLogInfo(
      'Method: $method\n'
      'Url: $url\n'
      'Token: ${rawToken ?? ''}\n'
      'Body: ${_formatBody(body ?? (queryParams ?? const <String, dynamic>{}))}',
    );
  }

  static void _logResponse({
    required String method,
    required String url,
  
    required Response<dynamic> response,
  }) {
    final authToken = response.requestOptions.headers['Authorization'];
    final rawToken = authToken?.toString().replaceFirst('Bearer ', '');
    final reqBody =
        response.requestOptions.data ?? response.requestOptions.queryParameters;
    _debugLogInfo(
      'Method: $method\n'
      'Url: $url\n'
      'Token: ${rawToken ?? ''}\n'
      'Body: ${_formatBody(reqBody)}\n'
      'Response: ${response.data}',
    );
  }

  static BaseOptions _baseOptions() {
    return BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      validateStatus: (status) => status != null && status < 500,
    );
  }

  static Map<String, dynamic> _buildHeaders({
    required String? token,
    required bool isTokenRequired,
    bool isFormData = false,
  }) {
    final headers = <String, dynamic>{};

    if (isTokenRequired && token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    if (isFormData) {
      headers['Content-Type'] = 'multipart/form-data';
    }

    return headers;
  }

  static Future<bool> _shouldForceLogout(Response<dynamic>? response) async {
    if (response == null) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final localToken = prefs.getString('token');
    final hasLocalToken = localToken != null && localToken.isNotEmpty;
    final statusCode = response.statusCode;

    var message = '';
    final data = response.data;
    if (data is Map<String, dynamic>) {
      message = (data['message'] ?? '').toString().toLowerCase();
    }

    if (statusCode != 401 && !message.contains('no token provided')) {
      return false;
    }

    if (!hasLocalToken) {
      return true;
    }

    return message.contains('token expired') ||
        message.contains('jwt expired') ||
        message.contains('invalid token') ||
        message.contains('invalid signature') ||
        message.contains('session expired') ||
        message.contains('unauthorized');
  }

  static Future<void> _handleUnauthorized() async {
    if (_isHandlingUnauthorized) return;
    _isHandlingUnauthorized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove('refreshToken');
      await prefs.remove('sessionToken');
      await prefs.remove('role');
      await prefs.remove('contacts_synced');
      await prefs.remove('userId');
      await prefs.remove('driverId');

      SocketService().dispose();

      if (Get.isRegistered<ProfleCotroller>()) {
        Get.find<ProfleCotroller>().clearSession();
      }

      Get.offAll(() => const MobileScreens());
    } catch (e) {
      _debugLogError('Unauthorized logout failed: $e');
    } finally {
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        _isHandlingUnauthorized = false;
      });
    }
  }

  static Future<void> _handleUnauthorizedIfNeeded(
    Response<dynamic>? response,
  ) async {
    if (await _shouldForceLogout(response)) {
      _debugLogError('Unauthorized response received. Redirecting to login.');
      await _handleUnauthorized();
      return;
    }

    if (response?.statusCode == 401) {
      _debugLogError(
        'Received 401 from server while a local token exists. '
        'Skipping forced logout for this response.',
      );
    }
  }

  static Future<dynamic> sendRequest(
    String url,
    Map<String, dynamic> body,
    String? method,

    bool isTokenRequired  ,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    final dio = Dio(_baseOptions());
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          return handler.next(options);
        },
        onResponse: (
          Response<dynamic> response,
          ResponseInterceptorHandler handler,
        ) {
          // Keep logs debug-only and standardized via _logResponse().
          return handler.next(response);
        },
        onError: (DioException error, ErrorInterceptorHandler handler) async {
          _debugLogError('POST API interceptor error: $url\nERROR: $error');
          await _handleUnauthorizedIfNeeded(error.response);
          if (error.response?.statusCode == 402) {
            return handler.reject(error);
          } else if (error.response?.statusCode == 406 ||
              error.response?.statusCode == 401) {
            return handler.reject(error);
          } else if (error.response?.statusCode == 429) {
            return handler.reject(error);
          } else if (error.response?.statusCode == 409) {
            return handler.reject(error);
          }
          return handler.next(error);
        },
      ),
    );

    try {
      final headers = _buildHeaders(
        token: token,
        isTokenRequired: true,
      );
      final upperMethod = (method ?? 'POST').toUpperCase();

      _logRequest(
        method: upperMethod,
        url: url,
        headers: headers,
        body: body,
      );

      late final Response response;
      if (upperMethod == 'GET') {
        response = await dio.get(
          url,
          queryParameters: body,
          options: Options(headers: headers),
        );
      } else {
        response = await dio.post(
          url,
          data: body,
          options: Options(headers: headers),
        );
      }

      _logResponse(method: upperMethod, url: url, response: response);
      await _handleUnauthorizedIfNeeded(response);
      return response;
    } catch (e, st) {
      _debugLogError('API ERROR: $url\nERROR: $e\nSTACK: $st');
      return e;
    }
  }

  /// Customer logout call that should never block UI navigation.
  ///
  /// Call this with `unawaited(...)` from the UI layer.
  static Future<void> sendLogoutFireAndForget({
    required String url,
    required String? token,
  }) async {
    final dio = Dio(_baseOptions());
    final headers = _buildHeaders(
      token: token,
      isTokenRequired: token != null && token.trim().isNotEmpty,
    );

    try {
      await dio.post(
        url,
        data: const <String, dynamic>{},
        options: Options(headers: headers),
      );
    } catch (e) {
      _debugLogError('Logout API failed: $e');
    }
  }

  static Future<dynamic> formData(
    String url,
    dynamic body,
    String? method,
    bool isTokenRequired,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    final dio = Dio(_baseOptions());
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          return handler.next(options);
        },
        onResponse: (
          Response<dynamic> response,
          ResponseInterceptorHandler handler,
        ) {
          // Keep logs debug-only and standardized via _logResponse().
          return handler.next(response);
        },
        onError: (DioException error, ErrorInterceptorHandler handler) async {
          _debugLogError('FORM API interceptor error: $url\nERROR: $error');
          await _handleUnauthorizedIfNeeded(error.response);
          if (error.response?.statusCode == 402) {
            return handler.reject(error);
          } else if (error.response?.statusCode == 406 ||
              error.response?.statusCode == 401) {
            return handler.reject(error);
          } else if (error.response?.statusCode == 429) {
            return handler.reject(error);
          } else if (error.response?.statusCode == 409) {
            return handler.reject(error);
          }
          return handler.next(error);
        },
      ),
    );

    try {
      final headers = _buildHeaders(
        token: token,
        isTokenRequired: isTokenRequired,
        isFormData: body is FormData,
      );

      _logRequest(
        method: 'POST(FORM)',
        url: url,
        headers: headers,
        body: body,
      );

      final response = await dio.post(
        url,
        data: body,
        options: Options(headers: headers),
      );

      _logResponse(method: 'POST(FORM)', url: url, response: response);
      await _handleUnauthorizedIfNeeded(response);
      return response;
    } catch (e, st) {
      _debugLogError('API ERROR: $url\nERROR: $e\nSTACK: $st');
      return e;
    }
  }

  static Future<Response?> sendGetRequest(
    String url,
    Map<String, dynamic> queryParams,
    String method,
    bool isTokenRequired,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    final headers = _buildHeaders(
      token: token,
      isTokenRequired: isTokenRequired,
    );

    final dio = Dio(_baseOptions())..options.headers.addAll(headers);

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          options.headers.addAll(headers);
          _logRequest(
            method: method.isEmpty ? 'GET' : method,
            url: options.uri.toString(),
            headers: Map<String, dynamic>.from(options.headers),
            queryParams: queryParams,
          );
          return handler.next(options);
        },
        onResponse: (
          Response<dynamic> response,
          ResponseInterceptorHandler handler,
        ) {
          _logResponse(
            method: 'GET',
            url: response.requestOptions.uri.toString(),
            response: response,
          );
          return handler.next(response);
        },
        onError: (DioException error, ErrorInterceptorHandler handler) async {
          _debugLogError('GET API interceptor error: ${error.requestOptions.uri}\nERROR: $error');
          await _handleUnauthorizedIfNeeded(error.response);
          if (error.response?.statusCode == 402) {
            return handler.reject(error);
          } else if (error.response?.statusCode == 406 ||
              error.response?.statusCode == 401) {
            return handler.reject(error);
          } else if (error.response?.statusCode == 429) {
            return handler.reject(error);
          } else if (error.response?.statusCode == 409) {
            return handler.reject(error);
          }
          return handler.next(error);
        },
      ),
    );

    try {
      final response = await dio.get(
        url,
        queryParameters: queryParams,
        options: Options(headers: headers),
      );

      await _handleUnauthorizedIfNeeded(response);
      return response;
    } catch (e, st) {
      _debugLogError('GET API ERROR: $url\nERROR: $e\nSTACK: $st');
      return null;
    }
  }
}
// import 'dart:async';
// import 'package:flutter/foundation.dart';

// import 'package:hopper/Core/Consents/app_logger.dart';
// import 'package:dio/dio.dart';
// import 'package:get/get.dart' hide FormData, Response;
// import 'package:hopper/Presentation/Authentication/screens/mobile_screens.dart';
// import 'package:hopper/uitls/websocket/socket_io_client.dart';
// import 'package:shared_preferences/shared_preferences.dart';

// class Request {
//   static bool _isHandlingUnauthorized = false;

//   static void _logInfo(String message) {
//     AppLogger.log.i(message);
//     debugPrint(message);
//   }

//   static void _logError(String message) {
//     AppLogger.log.e(message);
//     debugPrint(message);
//   }

//   static String _formatBody(dynamic body) {
//     if (body == null) return '{}';
//     if (body is FormData) {
//       final fields = body.fields
//           .map((e) => '${e.key}: ${e.value}')
//           .toList(growable: false);
//       final files = body.files
//           .map((e) {
//             final f = e.value;
//             return '${e.key}: {'
//                 'filename: ${f.filename}, '
//                 'length: ${f.length}, '
//                 'contentType: ${f.contentType}'
//                 '}';
//           })
//           .toList(growable: false);
//       return 'FormData{fields: $fields, files: $files}';
//     }
//     return body.toString();
//   }

//   static void _logRequest({
//     required String method,
//     required String url,
//     required Map<String, dynamic> headers,
//     dynamic body,
//     Map<String, dynamic>? queryParams,
//   }) {
//     final safeHeaders = Map<String, dynamic>.from(headers);
//     if (safeHeaders['Authorization'] != null &&
//         safeHeaders['Authorization'].toString().isNotEmpty) {
//       safeHeaders['Authorization'] = 'Bearer ***';
//     }
//     _logInfo(
//       'REQUEST [$method]\n'
//       'URL: $url\n'
//       'HEADERS: $safeHeaders\n'
//       'QUERY: ${queryParams ?? {}}\n'
//       'BODY: ${_formatBody(body)}',
//     );
//   }

//   static void _logResponse({
//     required String method,
//     required String url,
//     required Response<dynamic> response,
//   }) {
//     _logInfo(
//       'RESPONSE [$method]\n'
//       'URL: $url\n'
//        'STATUS: ${response.statusCode}\n'
//       'DATA: ${response.data}',
//     );
//   }

//   static BaseOptions _baseOptions() {
//     return BaseOptions(
//       connectTimeout: const Duration(seconds: 10),
//       receiveTimeout: const Duration(seconds: 15),
//       validateStatus: (status) => status != null && status < 500,
//     );
//   }

//   static Map<String, dynamic> _buildHeaders({
//     required String? token,
//     required bool isTokenRequired,
//     bool isFormData = false,
//   }) {
//     final headers = <String, dynamic>{};

//     if (isTokenRequired && token != null && token.isNotEmpty) {
//       headers['Authorization'] = 'Bearer $token';
//     }

//     if (isFormData) {
//       headers['Content-Type'] = 'multipart/form-data';
//     }

//     return headers;
//   }

//   static Future<bool> _shouldForceLogout(Response<dynamic>? response) async {
//     if (response == null) {
//       return false;
//     }

//     final prefs = await SharedPreferences.getInstance();
//     final localToken = prefs.getString('token');
//     final hasLocalToken = localToken != null && localToken.isNotEmpty;
//     final statusCode = response.statusCode;

//     var message = '';
//     final data = response.data;
//     if (data is Map<String, dynamic>) {
//       message = (data['message'] ?? '').toString().toLowerCase();
//     }

//     if (statusCode != 401 && !message.contains('no token provided')) {
//       return false;
//     }

//     if (!hasLocalToken) {
//       return true;
//     }

//     return message.contains('token expired') ||
//         message.contains('jwt expired') ||
//         message.contains('invalid token') ||
//         message.contains('invalid signature') ||
//         message.contains('session expired') ||
//         message.contains('unauthorized');
//   }

//   static Future<void> _handleUnauthorized() async {
//     if (_isHandlingUnauthorized) return;
//     _isHandlingUnauthorized = true;

//     try {
//       final prefs = await SharedPreferences.getInstance();
//       await prefs.remove('token');
//       await prefs.remove('refreshToken');
//       await prefs.remove('sessionToken');
//       await prefs.remove('role');
//       await prefs.remove('contacts_synced');
//       await prefs.remove('userId');
//       await prefs.remove('driverId');

//       SocketService().dispose();

//       Get.offAll(() => const MobileScreens());
//     } catch (e) {
//       _logError('Unauthorized logout failed: $e');
//     } finally {
//       Future<void>.delayed(const Duration(milliseconds: 300), () {
//         _isHandlingUnauthorized = false;
//       });
//     }
//   }

//   static Future<void> _handleUnauthorizedIfNeeded(
//     Response<dynamic>? response,
//   ) async {
//     if (await _shouldForceLogout(response)) {
//       _logError('Unauthorized response received. Redirecting to login.');
//       await _handleUnauthorized();
//       return;
//     }

//     if (response?.statusCode == 401) {
//       _logError(
//         'Received 401 from server while a local token exists. '
//         'Skipping forced logout for this response.',
//       );
//     }
//   }

//   static Future<dynamic> sendRequest(
//     String url,
//     Map<String, dynamic> body,
//     String? method,
//     bool isTokenRequired,
//   ) async {
//     final prefs = await SharedPreferences.getInstance();
//     final token = prefs.getString('token');

//     final dio = Dio(_baseOptions());
//     dio.interceptors.add(
//       InterceptorsWrapper(
//         onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
//           return handler.next(options);
//         },
//         onResponse: (
//           Response<dynamic> response,
//           ResponseInterceptorHandler handler,
//         ) {
//           _logInfo(
//             'sendPostRequest \n API: $url \n RESPONSE: ${response.toString()}',
//           );
//           return handler.next(response);
//         },
//         onError: (DioException error, ErrorInterceptorHandler handler) async {
//           _logError('POST API interceptor error: $url \n ERROR: $error');
//           await _handleUnauthorizedIfNeeded(error.response);
//           if (error.response?.statusCode == 402) {
//             return handler.reject(error);
//           } else if (error.response?.statusCode == 406 ||
//               error.response?.statusCode == 401) {
//             return handler.reject(error);
//           } else if (error.response?.statusCode == 429) {
//             return handler.reject(error);
//           } else if (error.response?.statusCode == 409) {
//             return handler.reject(error);
//           }
//           return handler.next(error);
//         },
//       ),
//     );

//     try {
//       final headers = _buildHeaders(
//         token: token,
//         isTokenRequired: true,
//       );
//       final upperMethod = (method ?? 'POST').toUpperCase();
//       _logRequest(method: upperMethod, url: url, headers: headers, body: body);

//       late final Response response;
//       if (upperMethod == 'GET') {
//         response = await dio.get(
//           url,
//           queryParameters: body,
//           options: Options(headers: headers),
//         );
//       } else {
//         response = await dio.post(
//           url,
//           data: body,
//           options: Options(headers: headers),
//         );
//       }

//       _logResponse(method: upperMethod, url: url, response: response);
//       await _handleUnauthorizedIfNeeded(response);
//       return response;
//     } catch (e, st) {
//       _logError('API: $url \n ERROR: $e \n STACK: $st');
//       return e;
//     }
//   }

//   static Future<dynamic> formData(
//     String url,
//     dynamic body,
//     String? method,
//     bool isTokenRequired,
//   ) async {
//     final prefs = await SharedPreferences.getInstance();
//     final token = prefs.getString('token');

//     final dio = Dio(_baseOptions());
//     dio.interceptors.add(
//       InterceptorsWrapper(
//         onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
//           return handler.next(options);
//         },
//         onResponse: (
//           Response<dynamic> response,
//           ResponseInterceptorHandler handler,
//         ) {
//           _logInfo(
//             'sendPostRequest \n API: $url \n RESPONSE: ${response.toString()}',
//           );
//           return handler.next(response);
//         },
//         onError: (DioException error, ErrorInterceptorHandler handler) async {
//           _logError('FORM API interceptor error: $url \n ERROR: $error');
//           await _handleUnauthorizedIfNeeded(error.response);
//           if (error.response?.statusCode == 402) {
//             return handler.reject(error);
//           } else if (error.response?.statusCode == 406 ||
//               error.response?.statusCode == 401) {
//             return handler.reject(error);
//           } else if (error.response?.statusCode == 429) {
//             return handler.reject(error);
//           } else if (error.response?.statusCode == 409) {
//             return handler.reject(error);
//           }
//           return handler.next(error);
//         },
//       ),
//     );

//     try {
//       final headers = _buildHeaders(
//         token: token,
//         isTokenRequired: true,
//         isFormData: body is FormData,
//       );
//       _logRequest(method: 'POST(FORM)', url: url, headers: headers, body: body);
//       final response = await dio.post(
//         url,
//         data: body,
//         options: Options(headers: headers),
//       );

//       _logResponse(method: 'POST(FORM)', url: url, response: response);
//       await _handleUnauthorizedIfNeeded(response);
//       return response;
//     } catch (e, st) {
//       _logError('API: $url \n ERROR: $e \n STACK: $st');
//       return e;
//     }
//   }

//   static Future<Response?> sendGetRequest(
//     String url,
//     Map<String, dynamic> queryParams,
//     String method,
//     bool isTokenRequired,
//   ) async {
//     final prefs = await SharedPreferences.getInstance();
//     final token = prefs.getString('token');
//     final headers = _buildHeaders(
//       token: token,
//       isTokenRequired: true,
//     );

//     final dio = Dio(_baseOptions())..options.headers.addAll(headers);
//     dio.interceptors.add(
//       InterceptorsWrapper(
//         onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
//           options.headers.addAll(headers);
//           _logRequest(
//             method: method.isEmpty ? 'GET' : method,
//             url: options.uri.toString(),
//             headers: Map<String, dynamic>.from(options.headers),
//             queryParams: queryParams,
//           );
//           return handler.next(options);
//         },
//         onResponse: (
//           Response<dynamic> response,
//           ResponseInterceptorHandler handler,
//         ) {
//           _logResponse(
//             method: 'GET',
//             url: response.requestOptions.uri.toString(),
//             response: response,
//           );
//           return handler.next(response);
//         },
//         onError: (DioException error, ErrorInterceptorHandler handler) async {
//           _logError(
//             'GET API interceptor error: ${error.requestOptions.uri} \n'
//             'HEADERS: ${error.requestOptions.headers} \n'
//             'ERROR: $error',
//           );
//           await _handleUnauthorizedIfNeeded(error.response);
//           if (error.response?.statusCode == 402) {
//             return handler.reject(error);
//           } else if (error.response?.statusCode == 406 ||
//               error.response?.statusCode == 401) {
//             return handler.reject(error);
//           } else if (error.response?.statusCode == 429) {
//             return handler.reject(error);
//           } else if (error.response?.statusCode == 409) {
//             return handler.reject(error);
//           }
//           return handler.next(error);
//         },
//       ),
//     );

//     try {
//       final response = await dio.get(
//         url,
//         queryParameters: queryParams,
//         options: Options(headers: headers),
//       );

//       await _handleUnauthorizedIfNeeded(response);
//       return response;
//     } catch (e, st) {
//       _logError('GET API: $url \n ERROR: $e \n STACK: $st');
//       return null;
//     }
//   }
// }
