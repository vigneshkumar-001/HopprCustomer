import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:hopper/Presentation/Drawer/models/ride_history_response.dart';
import 'package:hopper/Presentation/wallet/model/get_wallet_balance_response.dart';
import 'package:hopper/Presentation/wallet/model/transaction_response.dart';
import 'package:hopper/Presentation/wallet/model/wallet_response.dart';
import 'package:hopper/Presentation/wallet/screens/wallet_payment_screens.dart';

import 'package:hopper/api/dataSource/apiDataSource.dart';

class WalletController extends GetxController {
  final ApiDataSource apiDataSource = ApiDataSource();
  Rx<WalletBalance?> walletBalance = Rx<WalletBalance?>(null);
  Rx<WalletResponse?> walletData = Rx<WalletResponse?>(null);
  RxList<Transaction> transactions = <Transaction>[].obs;
  RxList<Transaction> traction = RxList<Transaction>([]);
  RxDouble balance = 0.0.obs;

  /// Pagination state
  RxBool isLoading = false.obs; // First API call
  RxBool isMoreLoading = false.obs; // Pagination loader
  int page = 1;
  final int limit = 10;
  RxBool hasMore = true.obs;

  @override
  void onInit() {
    super.onInit();
    customerWalletHistory(isRefresh: true);
    getWalletBalance();
  }

  void resetPagination() {
    page = 1;
    transactions.clear();
    isLoading.value = true;
    isMoreLoading.value = false;
  }

  /// ----------------------------
  /// GET WALLET BALANCE
  /// ----------------------------
  Future<void> getWalletBalance() async {
    try {
      final result = await apiDataSource.getWalletBalance();
      result.fold((failure) => AppLogger.log.e("❌ Failed: $failure"), (
        response,
      ) {
        walletBalance.value = response.data;
        // balance.value =
        //     double.tryParse(response.data?.customerWalletBalance ?? "0") ??
        //         0.0;
      });
    } catch (e) {
      AppLogger.log.e("❌ Exception: $e");
    }
  }

  Future<void> addWallet({
    required double amount,
    required BuildContext context,
    required String method,
  }) async {
    isLoading.value = true;
    try {
      final results = await apiDataSource.addWallet(
        amount: amount,
        method: method,
      );
      results.fold(
        (failure) {
          AppToasts.showError(context,failure.message);
          AppLogger.log.e("❌ Ride history fetch failed: $failure");
        },
        (response) {
          walletData.value = response;
          Get.to(
            () => WalletPaymentScreens(
              clientSecret: response.clientSecret,
              publishableKey: response.publishableKey,
              transactionId: response.transactionId,
              amount: amount.toInt(),
            ),
          );
          AppLogger.log.i("✅ Raw response: ${response.toJson()}");
        },
      );
    } catch (e) {
      AppLogger.log.e("❌ Exception while fetching rides: $e");
    } finally {
      isLoading.value = false;
    }
  }

  /// ----------------------------
  /// FETCH WALLET TRANSACTIONS (Pagination)
  /// ----------------------------
  Future<void> customerWalletHistory({bool isRefresh = false}) async {
    // ⛔ BLOCK pagination while the first load is running
    if (isLoading.value && !isRefresh) return;

    if (isRefresh) {
      page = 1;
      hasMore.value = true;
      transactions.clear();
      isLoading.value = true;
      isMoreLoading.value = false;
    } else {
      if (!hasMore.value) return;
      isMoreLoading.value = true;
    }

    try {
      final result = await apiDataSource.customerWalletHistory(page: page);

      result.fold((failure) => AppLogger.log.e("❌ History Failed: $failure"), (
        response,
      ) {
        List<Transaction> fetched = response.transactions;

        // Set data
        if (isRefresh) {
          transactions.assignAll(fetched);
        } else {
          transactions.addAll(fetched);
        }

        // Update balance
        balance.value = double.tryParse(response.balance) ?? 0.0;

        // Pagination logic
        if (fetched.length < limit) {
          hasMore.value = false;
        } else {
          page++;
        }

        AppLogger.log.i("📌 PAGE LOADED → $page, ITEMS: ${fetched.length}");
      });
    } catch (e) {
      AppLogger.log.e("❌ History Exception: $e");
    } finally {
      isLoading.value = false;
      isMoreLoading.value = false;
    }
  }
}

// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:hopper/Core/Consents/app_logger.dart';
// import 'package:hopper/Core/Utility/app_toasts.dart';
// import 'package:hopper/Presentation/Drawer/models/ride_history_response.dart';
// import 'package:hopper/Presentation/wallet/model/get_wallet_balance_response.dart';
// import 'package:hopper/Presentation/wallet/model/transaction_response.dart';
// import 'package:hopper/Presentation/wallet/model/wallet_response.dart';
// import 'package:hopper/Presentation/wallet/screens/wallet_payment_screens.dart';
//
// import 'package:hopper/api/dataSource/apiDataSource.dart';
//
// class WalletController extends GetxController {
//   final ApiDataSource apiDataSource = ApiDataSource();
//   Rx<WalletResponse?> walletData = Rx<WalletResponse?>(null);
//   Rx<WalletBalance?> walletBalance = Rx<WalletBalance?>(null);
//   RxList<Transaction> traction = RxList<Transaction>([]);
//
//   final RxBool isLoading = false.obs;
//   var balance = 0.0.obs; // Observable double
//   @override
//   void onInit() {
//     super.onInit();
//     getWalletBalance();
//     customerWalletHistory();
//   }
//
//   Future<void> addWallet({
//     required double amount,
//     required String method,
//   }) async {
//     isLoading.value = true;
//     try {
//       final results = await apiDataSource.addWallet(
//         amount: amount,
//         method: method,
//       );
//       results.fold(
//         (failure) {
//           AppToasts.showError(failure.message);
//           AppLogger.log.e("❌ Ride history fetch failed: $failure");
//         },
//         (response) {
//           walletData.value = response;
//           Get.to(
//             () => WalletPaymentScreens(
//               clientSecret: response.clientSecret,
//               publishableKey: response.publishableKey,
//               transactionId: response.transactionId,
//
//               amount: amount.toInt(),
//             ),
//           );
//           AppLogger.log.i("✅ Raw response: ${response.toJson()}");
//         },
//       );
//     } catch (e) {
//       AppLogger.log.e("❌ Exception while fetching rides: $e");
//     } finally {
//       isLoading.value = false;
//     }
//   }
//
//   Future<String?> getWalletBalance() async {
//     isLoading.value = true;
//     try {
//       final results = await apiDataSource.getWalletBalance();
//       results.fold(
//         (failure) {
//           AppLogger.log.e("❌ Ride history fetch failed: $failure");
//         },
//         (response) {
//           walletBalance.value = response.data;
//           AppLogger.log.i("✅ Raw response: ${response.toJson()}");
//           return response.data.toString();
//         },
//       );
//     } catch (e) {
//       AppLogger.log.e("❌ Exception while fetching rides: $e");
//     } finally {
//       isLoading.value = false;
//     }
//     return null;
//   }
//
//   Future<void> customerWalletHistory() async {
//     isLoading.value = true;
//     try {
//       final results = await apiDataSource.customerWalletHistory();
//       results.fold(
//         (failure) {
//           AppLogger.log.e("❌ Ride history fetch failed: $failure");
//         },
//         (response) {
//           traction.value = response.transactions;
//           balance.value =
//               double.tryParse(response.balance) ?? 0.0; // ✅ parse string
//           AppLogger.log.i("✅ Raw response: ${response}");
//           return response.transactions.toString();
//         },
//       );
//     } catch (e) {
//       AppLogger.log.e("❌ Exception while fetching rides: $e");
//     } finally {
//       isLoading.value = false;
//     }
//     return null;
//   }
// }
