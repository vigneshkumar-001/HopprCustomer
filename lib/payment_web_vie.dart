import 'dart:convert';
import 'package:flutter/material.dart';
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
  bool _hasNavigatedBack = false; // Prevent multiple pops

  @override
  void initState() {
    super.initState();

    _controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageFinished: (url) async {
                _handleRedirect(url);
                await _checkJsonResponse();
              },
            ),
          )
          ..loadRequest(Uri.parse(widget.url));
  }

  void _handleRedirect(String url) {
    if (_hasNavigatedBack) return;

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    final status = uri.queryParameters['status']?.toLowerCase();

    if (status == 'successful') {
      final txRef = uri.queryParameters['tx_ref'];
      final transactionId = uri.queryParameters['transaction_id'];
      _pop({
        "status": "success",
        "txRef": txRef,
        "transactionId": transactionId,
      });
      return;
    }

    if (status == 'failed' || status == 'cancelled') {
      _pop({"status": "failure"});
      return;
    }
  }

  Future<void> _checkJsonResponse() async {
    if (_hasNavigatedBack) return;
    try {
      final content = await _controller.runJavaScriptReturningResult(
        "document.body.innerText",
      );
      if (content != null) {
        final text = content.toString();
        final data = jsonDecode(text);
        if (data is Map && data.containsKey('success')) {
          _pop({
            "status": data['success'] == true ? "success" : "failure",
            "message": data['message'] ?? "",
          });
        }
      }
    } catch (_) {
      // ignore parsing errors
    }
  }

  void _pop(Map<String, dynamic> result) {
    if (_hasNavigatedBack) return;
    _hasNavigatedBack = true;
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
          onPressed: () => _pop({"status": "failure"}), // Manual close
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
//                 if (widget.page != "wallet") {
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
//                   if (request.url.contains("flutterwave/FAILED")) {
//                     Navigator.pop(context, {"status": "failure"});
//                     return NavigationDecision.prevent;
//                   }
//                 } else {
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
//                   if (request.url.startsWith(
//                     "https://hoppr-face-two-dbe557472d7f.herokuapp.com/api/customer/wallet-callback?status=FAILED",
//                   )) {
//                     Navigator.pop(context, {"status": "FAILED"});
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
