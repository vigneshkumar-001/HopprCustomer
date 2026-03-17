import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/material.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Consents/app_logger.dart';

class PaypalWebviewPage extends StatefulWidget {
  final String amount;
  final String bookingId;

  const PaypalWebviewPage({
    super.key,
    required this.amount,
    required this.bookingId,
  });

  @override
  State<PaypalWebviewPage> createState() => _PaypalWebviewPageState();
}

class _PaypalWebviewPageState extends State<PaypalWebviewPage> {
  InAppWebViewController? webViewController;

  @override
  Widget build(BuildContext context) {
    final String url =
        "https://hoppr-face-two-dbe557472d7f.herokuapp.com/api/paypal?amount=${widget.amount}&userBookingId=${widget.bookingId}";

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.commonWhite,
        title: Text("PayPal Payment"),
      ),
      body: Center(
        child: InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri(url), // ✅ WebUri is required in new versions
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;

            // ✅ Listening for payment status from JavaScript
            controller.addJavaScriptHandler(
              handlerName: "paymentStatus",
              callback: (args) {
                final status = args.isNotEmpty ? args[0] : {};
                AppLogger.log.i(status);
                AppLogger.log.i(args);
                if (status['status'] == 'success') {
                  // Payment success
                  Navigator.pop(context, true);
                } else {
                  // Payment failed / cancelled
                  Navigator.pop(context, false);
                }
                return status;
              },
            );
          },
          onLoadStop: (controller, url) async {
            debugPrint("✅ Webview loaded: $url");
          },
          onLoadError: (controller, url, code, message) {
            debugPrint("❌ Webview error: $message");
          },
        ),
      ),
    );
  }
}
