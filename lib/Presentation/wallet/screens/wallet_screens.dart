import 'package:flutter/material.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/app_loader.dart';
import 'package:hopper/Core/Utility/empty_state_view.dart';
import 'package:hopper/Core/Utility/skeleton_loaders.dart';
import 'package:hopper/Presentation/Authentication/widgets/textFields.dart';
import 'package:hopper/Presentation/wallet/controller/wallet_controller.dart';
import 'package:get/get.dart';
import 'package:hopper/Presentation/wallet/model/transaction_response.dart';
import 'package:hopper/Presentation/wallet/screens/add_money_screen.dart';

class WalletScreen extends StatefulWidget {
  final String? flag;
  const WalletScreen({super.key, this.flag});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  late final WalletController walletController;
  late final bool _walletControllerWasRegistered;
  final ScrollController _scrollController = ScrollController();

  int selectedTab = 0;
  bool _isAmountVisible = false;

  @override
  void initState() {
    super.initState();
    _walletControllerWasRegistered = Get.isRegistered<WalletController>();
    walletController =
        _walletControllerWasRegistered
            ? Get.find<WalletController>()
            : Get.put(WalletController());
    _scrollController.addListener(_paginationListener);

    // If the controller already existed (e.g., used elsewhere like Payment),
    // refresh on open so Wallet always shows the latest balance/history.
    if (_walletControllerWasRegistered) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        walletController.refreshWallet();
      });
    }
  }

  void _paginationListener() {
    if (walletController.isLoading.value) {
      return;
    }

    if (!walletController.isMoreLoading.value &&
        _scrollController.position.pixels >
            _scrollController.position.maxScrollExtent - 150) {
      walletController.customerWalletHistory();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.flag != "bottomBar",
      child: Scaffold(
        backgroundColor: AppColors.containerColor1,
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              await walletController.refreshWallet();
            },
            child: Obx(() {
              List<Transaction> all = walletController.transactions;
              final historyError = walletController.walletHistoryError.value;

              List<Transaction> filtered =
                  selectedTab == 0
                      ? all
                      : selectedTab == 1
                      ? all
                          .where((e) => e.color.toLowerCase() == "green")
                          .toList()
                      : all
                          .where((e) => e.color.toLowerCase() == "red")
                          .toList();

              return ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 30),

                  /// BALANCE CARD
                  _buildBalanceCard(),

                  const SizedBox(height: 20),
                  const Text(
                    "Recent Transactions",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),

                  const SizedBox(height: 12),
                  _buildTabs(),

                  const SizedBox(height: 16),

                  if (walletController.isLoading.value &&
                      walletController.transactions.isEmpty)
                    SkeletonLoaders.walletHistory(),

                  if (!walletController.isLoading.value &&
                      historyError != null &&
                      walletController.transactions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: EmptyStateView(
                        image: AppImages.errorServer,
                        title: "Something went wrong",
                        subtitle:
                            "We couldn't load your wallet history. Please try again.",
                        onRetry: walletController.refreshWallet,
                      ),
                    ),

                  if (!walletController.isLoading.value &&
                      historyError == null &&
                      filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: EmptyStateView(
                        image: AppImages.emptyWallet,
                        title: "No transactions yet",
                        subtitle:
                            "Your wallet top-ups, payments and refunds will appear here.",
                      ),
                    ),

                  /// LIST ITEMS
                  ...filtered.map((tx) {
                    return buildTransaction(
                      subtitle2: tx.createdAt,
                      image: _getImageByType(tx.imageType),
                      title: tx.displayText,
                      subtitle: tx.walletDescription,
                      amount: '\u20A6 ${tx.amount.toStringAsFixed(2)}',
                      amountColor:
                          tx.color.toLowerCase() == "green"
                              ? Colors.green
                              : Colors.red,
                    );
                  }).toList(),

                  /// PAGINATION LOADER
                  if (walletController.isMoreLoading.value)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(child: AppLoader.circularLoader()),
                    ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        if (widget.flag != "bottomBar")
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Image.asset(AppImages.backImage, height: 19, width: 19),
          ),
        const Spacer(),
        CustomTextFields.textWithStyles700('Wallet', fontSize: 20),
        const Spacer(),
      ],
    );
  }

  Widget _buildTabs() {
    return Row(
      children: [
        buildTab("All", 0),
        const SizedBox(width: 8),
        buildTab("Money In", 1),
        const SizedBox(width: 8),
        buildTab("Money Out", 2),
      ],
    );
  }

  String _getImageByType(String imageType) {
    switch (imageType) {
      case "Refund":
        return AppImages.refund;
      case "Bike":
        return AppImages.bikeImage;
      default:
        return AppImages.wallet_top;
    }
  }

  Widget _buildBalanceCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B61FF), Color(0xFF5B8EFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(
                AppImages.bWallet,
                height: 24,
                color: AppColors.commonWhite,
              ),
              SizedBox(width: 8),
              CustomTextFields.textWithStylesSmall(
                'Wallet Balance',
                fontSize: 15,
                colors: AppColors.commonWhite,
                fontWeight: FontWeight.w500,
              ),
              Spacer(),
              IconButton(
                onPressed: () {
                  setState(() {
                    _isAmountVisible = !_isAmountVisible;
                  });
                },
                icon: Icon(
                  _isAmountVisible ? Icons.visibility : Icons.visibility_off,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Visibility(
            visible: _isAmountVisible,
            replacement: CustomTextFields.textWithImage(
              text: '****',
              imagePath: AppImages.nBlackCurrency,
              fontWeight: FontWeight.w700,
              fontSize: 25,
              colors: AppColors.commonWhite,
              imageColors: AppColors.commonWhite,
              imageSize: 20,
            ),
            child: Obx(
              () => CustomTextFields.textWithImage(
                text: walletController.balance.value.toStringAsFixed(2),
                imagePath: AppImages.nBlackCurrency,
                fontWeight: FontWeight.w700,
                fontSize: 20,
                colors: AppColors.commonWhite,
                imageColors: AppColors.commonWhite,
                imageSize: 20,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    final data = walletController.walletBalance.value;
                    Get.to(
                      () => AddMoneyScreen(
                        minimumWalletAddBalance: data?.minimumWalletAddBalance,
                        customerWalletBalance: data?.customerWalletBalance,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: AppColors.commonWhite.withOpacity(0.10),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: CustomTextFields.textWithStyles600(
                    "Add Money",
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: AppColors.commonWhite.withOpacity(0.10),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: CustomTextFields.textWithStyles600(
                    "Withdraw",
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildTab(String text, int index) {
    bool isSelected = selectedTab == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget buildTransaction({
    required String image,
    required String title,
    required String subtitle,
    required String subtitle2,
    required String amount,
    required Color amountColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.commonWhite,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.circularClr,
            child: Image.asset(image, height: 35),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                Text(
                  subtitle2,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: amountColor,
                  fontSize: 14,
                ),
              ),
              const Text(
                'wallet',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
