import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class AppToasts {
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static ScaffoldMessengerState? _messenger(BuildContext? context) {
    return messengerKey.currentState ??
        (context == null ? null : ScaffoldMessenger.maybeOf(context));
  }

  /// Runs a ScaffoldMessenger action build-safely.
  ///
  /// Calling `showSnackBar()` while Flutter is in a build/layout/paint phase
  /// (e.g. from `initState`, `build`, or a synchronous controller path invoked
  /// during the first frame) throws "showSnackBar() cannot be called during
  /// build". When we detect that phase we defer the action to the next
  /// post-frame callback; otherwise we run it immediately. The messenger is
  /// resolved INSIDE the action so a deferred call still picks up a valid
  /// messenger (and re-checks `context.mounted`).
  static void _runOnMessenger(
    BuildContext? context,
    void Function(ScaffoldMessengerState messenger) action,
  ) {
    void run() {
      if (context != null && !context.mounted) return;
      final messenger = _messenger(context);
      if (messenger == null) return;
      action(messenger);
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    final inFrame =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks ||
        phase == SchedulerPhase.transientCallbacks;
    if (inFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) => run());
    } else {
      run();
    }
  }

  static void clearSnackBars() {
    _runOnMessenger(null, (m) => m.clearSnackBars());
  }

  static void hideCurrentSnackBar() {
    _runOnMessenger(null, (m) => m.hideCurrentSnackBar());
  }

  static void customToast(BuildContext context, String message) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Oops!",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(message, style: const TextStyle(fontSize: 15)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text("Ok"),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static SnackBar _successSnackBar(String message) {
    return SnackBar(
      content: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: Colors.green,
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  static void showSuccess(BuildContext context, String message) {
    _runOnMessenger(context, (m) {
      m
        ..clearSnackBars()
        ..showSnackBar(_successSnackBar(message));
    });
  }

  static void showSuccessGlobal(String message) {
    _runOnMessenger(null, (m) {
      m
        ..clearSnackBars()
        ..showSnackBar(_successSnackBar(message));
    });
  }

  static SnackBar _errorSnackBar(String message, String title) {
    return SnackBar(
      content: Row(
        children: [
          const Icon(Icons.error, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title.trim().isEmpty ? message : "$title: $message"),
          ),
        ],
      ),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  static void showError(
    BuildContext context,
    String message, {
    String title = "Error",
  }) {
    _runOnMessenger(context, (m) {
      m
        ..clearSnackBars()
        ..showSnackBar(_errorSnackBar(message, title));
    });
  }

  static void showErrorGlobal(String message, {String title = "Error"}) {
    _runOnMessenger(null, (m) {
      m
        ..clearSnackBars()
        ..showSnackBar(_errorSnackBar(message, title));
    });
  }

  static void showInfoGlobal(String message, {String title = "Info"}) {
    _runOnMessenger(null, (m) {
      m
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(child: Text("$title: $message")),
              ],
            ),
            backgroundColor: Colors.black,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
    });
  }
}
