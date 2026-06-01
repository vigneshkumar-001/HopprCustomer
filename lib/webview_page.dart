import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PaymentWebView extends StatefulWidget {
  final String url;
  final String? page;
  const PaymentWebView({super.key, required this.url, this.page});

  @override
  State<PaymentWebView> createState() => _PaymentWebViewState();
}

class _PaymentWebViewState extends State<PaymentWebView> {
  late final WebViewController _controller;
  bool _hasNavigatedBack = false;
  int _lastProgress = 0;
  int? _lastWebErrorCode;
  String? _lastWebErrorDesc;

  bool get _logEnabled => kDebugMode;

  void _logI(String msg) {
    if (!_logEnabled) return;
    AppLogger.log.i('[PAY_WEB] $msg');
  }

  void _logE(String msg) {
    if (!_logEnabled) return;
    AppLogger.log.e('[PAY_WEB] $msg');
  }

  String _redactUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;

    // Keep only safe/needed query params (avoid leaking tokens in logs).
    const allow = <String>{'status', 'tx_ref', 'transaction_id', 'trxref', 'reference'};
    final safeQ = <String, String>{};
    uri.queryParameters.forEach((k, v) {
      if (allow.contains(k)) safeQ[k] = v;
    });

    return Uri(
      scheme: uri.scheme,
      userInfo: '',
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      queryParameters: safeQ.isEmpty ? null : safeQ,
      fragment: '',
    ).toString();
  }

  @override
  void initState() {
    super.initState();

    _logI('init url=${_redactUrl(widget.url)}');

    _controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onProgress: (progress) {
                _lastProgress = progress;
                _logI('progress=$progress%');
              },
              onPageStarted: (url) {
                _logI('pageStarted url=${_redactUrl(url)}');
              },
              onPageFinished: (url) async {
                _logI('pageFinished url=${_redactUrl(url)} progress=$_lastProgress%');
                _handlePaymentRedirect(url);
                await _checkJsonResponse();
              },
              onNavigationRequest: (request) {
                _logI('navRequest url=${_redactUrl(request.url)} isMainFrame=${request.isMainFrame}');
                return NavigationDecision.navigate;
              },
              onWebResourceError: (err) {
                // `WebResourceError` API differs by webview_flutter version.
                // Some versions do not provide `failingUrl`.
                _lastWebErrorCode = err.errorCode;
                _lastWebErrorDesc = err.description;
                _logE(
                  'webError code=${err.errorCode} type=${err.errorType} desc=${err.description}',
                );
              },
            ),
          )
          ..loadRequest(Uri.parse(widget.url));
  }

  void _handlePaymentRedirect(String url) {
    if (_hasNavigatedBack) return;

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    final status = uri.queryParameters['status']?.toLowerCase();
    if (status != null) {
      _logI('redirect status=$status url=${_redactUrl(url)}');
    }

    if (status == 'successful') {
      final txRef = uri.queryParameters['tx_ref'];
      final transactionId = uri.queryParameters['transaction_id'];
      _logI('SUCCESS tx_ref=$txRef transaction_id=$transactionId');
      _pop({
        "status": "success",
        "txRef": txRef,
        "transactionId": transactionId,
      });
      return;
    }

    if (status == 'failed' || status == 'cancelled') {
      _logI('FAILURE status=$status');
      _pop({"status": "failure"});
      return;
    }
  }

  Future<void> _checkJsonResponse() async {
    if (_hasNavigatedBack) return;
    try {
      final pageContent = await _controller.runJavaScriptReturningResult(
        "document.body.innerText",
      );
      if (pageContent != null) {
        final text = pageContent.toString();
        if (text.length > 6) {
          _logI('body.innerText len=${text.length} sample=${text.substring(0, text.length > 140 ? 140 : text.length)}');
        }

        // Some WebView errors still "finish" a page and render a built-in
        // error document. Detect and return a structured failure so the caller
        // can show the right message / fallback.
        final lowered = text.toLowerCase();
        if (lowered.contains('web page not available') ||
            lowered.contains('err_address_unreachable') ||
            lowered.contains('err_name_not_resolved') ||
            lowered.contains('err_internet_disconnected')) {
          _pop({
            "status": "failure",
            "errorCode": _lastWebErrorCode,
            "error": _lastWebErrorDesc ?? text,
          });
          return;
        }

        final data = jsonDecode(text);
        if (data is Map && data.containsKey('success')) {
          _logI('jsonResult keys=${data.keys.toList()} success=${data['success']}');
          _pop({
            "status": data['success'] == true ? "success" : "failure",
            "message": data['message'] ?? "",
          });
        }
      }
    } catch (e) {
      _logE('jsonCheck error=$e');
    }
  }

  void _pop(Map<String, dynamic> result) {
    if (_hasNavigatedBack) return;
    _hasNavigatedBack = true;
    _logI('pop result=$result');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, result);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Payment"),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _pop({"status": "failure"}), // manual close
        ),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}

// import 'package:flutter/material.dart';
// import 'package:webview_flutter/webview_flutter.dart';
//
// class PaymentWebView extends StatefulWidget {
//   final String url;
//   final String? page;
//   const PaymentWebView({super.key, required this.url, this.page});
//
//   @override
//   State<PaymentWebView> createState() => _PaymentWebViewState();
// }
//
// class _PaymentWebViewState extends State<PaymentWebView> {
//   late final WebViewController _controller;
//
//   @override
//   void initState() {
//     super.initState();
//     _controller =
//         WebViewController()
//           ..setJavaScriptMode(JavaScriptMode.unrestricted)
//           ..setNavigationDelegate(
//             NavigationDelegate(
//               onNavigationRequest: (request) {
//                 print("Navigating to: ${request.url}");
//                 final uri = Uri.parse(request.url);
//
//                 if (widget.page == 'walet') {
//                   if (request.url.startsWith(
//                     "https://hoppr-face-two-dbe557472d7f.herokuapp.com/api/customer/wallet-callback?status=successful",
//                   )) {
//                     final txRef = uri.queryParameters["tx_ref"];
//                     final transactionId = uri.queryParameters["transaction_id"];
//                     Navigator.pop(context, {
//                       "status": "success",
//                       "txRef": txRef,
//                       "transactionId": transactionId,
//                     });
//                     return NavigationDecision.prevent;
//                   }
//
//                   // ❌ Payment Failure
//                   if (request.url.contains("flutterwave/fail")) {
//                     Navigator.pop(context, {"status": "failure"});
//                     return NavigationDecision.prevent;
//                   }
//                 } else {
//                   if (request.url.startsWith(
//                     "https://hoppr-face-two-dbe557472d7f.herokuapp.com/api/customer/flutterwave/callback?status=successful",
//                   )) {
//                     final txRef = uri.queryParameters["tx_ref"];
//                     final transactionId = uri.queryParameters["transaction_id"];
//                     Navigator.pop(context, {
//                       "status": "success",
//                       "txRef": txRef,
//                       "transactionId": transactionId,
//                     });
//                     return NavigationDecision.prevent;
//                   }
//
//                   // ❌ Payment Failure
//                   if (request.url.contains("flutterwave/fail")) {
//                     Navigator.pop(context, {"status": "failure"});
//                     return NavigationDecision.prevent;
//                   }
//                 }
//
//                 return NavigationDecision.navigate;
//               },
//             ),
//           )
//           ..loadRequest(Uri.parse(widget.url));
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text("Payment")),
//       body: WebViewWidget(controller: _controller),
//     );
//   }
// }
