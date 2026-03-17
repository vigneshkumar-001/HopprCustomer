import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/material.dart';
import 'package:hopper/Core/Consents/app_colors.dart';

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
  // WebView(
  // javascriptMode: JavascriptMode.unrestricted,
  // javascriptChannels: {
  // JavascriptChannel(
  // name: 'PayChannel',
  // onMessageReceived: (JavascriptMessage message) {
  // final data = jsonDecode(message.message);
  // if (data['type'] == 'paymentStatus') {
  // if (data['status'] == 'COMPLETED') {
  // Navigator.pop(context, {'success': true, 'transactionId': data['transactionId']});
  // } else {
  // Navigator.pop(context, {'success': false, 'transactionId': data['transactionId']});
  // }
  // } else if (data['type'] == 'paymentError') {
  // Navigator.pop(context, {'success': false, 'error': data['message']});
  // }
  // },
  // ),
  // },
  // // ...
  // );

  @override
  Widget build(BuildContext context) {
    final String url =
        "https://hoppr-face-two-dbe557472d7f.herokuapp.com/api/paypal?amount=${widget.amount}&userBookingId=${widget.bookingId}";

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.commonWhite,
        title: const Text("PayPal Payment"),
      ),
      body: Center(
        child: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(url)),
          onWebViewCreated: (controller) {
            webViewController = controller;

            controller.addJavaScriptHandler(
              handlerName: "paymentStatus",
              callback: (args) {
                final status = args.isNotEmpty ? args[0] : {};

                if (status['status'] == 'success') {
                  // Payment success
                  Navigator.pop(context, true);
                } else {
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
