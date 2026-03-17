// import 'package:flutter/material.dart';
// import 'package:hopper/Core/Consents/app_colors.dart';
// import 'package:hopper/Core/Utility/app_buttons.dart';
// import 'package:hopper/Core/Utility/app_images.dart';
// import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
// import 'package:get/get.dart';
//
// class AddMoneyScreen extends StatefulWidget {
//   const AddMoneyScreen({super.key});
//
//   @override
//   State<AddMoneyScreen> createState() => _AddMoneyScreenState();
// }
//
// class _AddMoneyScreenState extends State<AddMoneyScreen> {
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: SafeArea(
//         child: Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 15),
//           child: Column(
//             children: [
//               Expanded(
//                 child: SingleChildScrollView(
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Padding(
//                         padding: const EdgeInsets.symmetric(vertical: 20),
//                         child: Row(
//                           children: [
//                             CustomTextFields.textWithStyles700(
//                               'Add Money',
//                               fontSize: 20,
//                             ),
//                             const Spacer(),
//                             InkWell(
//                               onTap: () {
//                                 Get.back();
//                               },
//                               child: Container(
//                                 padding: const EdgeInsets.symmetric(
//                                   horizontal: 5,
//                                   vertical: 5,
//                                 ),
//                                 decoration: BoxDecoration(
//                                   color: AppColors.containerColor,
//                                   borderRadius: BorderRadius.circular(30),
//                                 ),
//                                 child: Image.asset(
//                                   AppImages.close,
//                                   height: 17,
//                                   width: 17,
//                                 ),
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//                       SizedBox(height: 30),
//                       CustomTextFields.textWithStyles700(
//                         'Add Money to Hoppr Wallet ',
//                         fontSize: 20,
//                       ),
//                       SizedBox(height: 5),
//                       Row(
//                         children: [
//                           CustomTextFields.textWithStylesSmall(
//                             fontWeight: FontWeight.w400,
//                             colors: AppColors.commonBlack,
//
//                             'Current balance : ',
//                             fontSize: 14,
//                           ),
//                           CustomTextFields.textWithImage(
//                             colors: AppColors.commonBlack,
//                             fontWeight: FontWeight.w400,
//                             fontSize: 14,
//                             text: '0.0',
//                             imagePath: AppImages.nBlackCurrency,
//                           ),
//                         ],
//                       ),
//                       SizedBox(height: 5),
//                       CustomTextFields.textWithStylesSmall(
//                         maxLines: 3,
//                         'Hoppr wallet can only be used to play for Rides and Packages on Hoppr',
//                         fontSize: 12,
//                         colors: AppColors.rideShareContainerColor2,
//                       ),
//                       SizedBox(height: 40),
//                       Center(
//                         child: SizedBox(
//                           width: 200,
//                           child: TextField(
//                             textAlign: TextAlign.center,
//                             keyboardType: TextInputType.number,
//                             style: const TextStyle(
//                               fontSize: 22,
//                               fontWeight: FontWeight.bold,
//                             ),
//                             decoration: const InputDecoration(
//                               hintText: "Enter amount",
//                               border: InputBorder.none, // No border
//                             ),
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//               Padding(
//                 padding: const EdgeInsets.symmetric(vertical: 10),
//                 child: AppButtons.button(
//                   onTap: () async {
//                     Get.to(AddMoneyScreen());
//                   },
//                   text: 'Add Money',
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }
import 'package:flutter/material.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/app_loader.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:hopper/Presentation/wallet/controller/wallet_controller.dart';
import 'package:get/get.dart';
import 'package:hopper/Presentation/wallet/screens/wallet_payment_screens.dart';

class AddMoneyScreen extends StatefulWidget {
  final String? minimumWalletAddBalance;
  final String? customerWalletBalance;
  const AddMoneyScreen({
    super.key,
    this.minimumWalletAddBalance,
    this.customerWalletBalance ,
  });

  @override
  State<AddMoneyScreen> createState() => _AddMoneyScreenState();
}

class _AddMoneyScreenState extends State<AddMoneyScreen> {
  final TextEditingController _amountController = TextEditingController();
  final WalletController controller = Get.put(WalletController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  children: [
                    const Text(
                      "Add Money",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: const Icon(Icons.close, size: 18),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Add Money to Hoppr Wallet",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          CustomTextFields.textWithStylesSmall(
                            fontWeight: FontWeight.w400,
                            colors: AppColors.commonBlack,
                            'Current balance : ',
                            fontSize: 14,
                          ),
                          CustomTextFields.textWithImage(
                            colors: AppColors.commonBlack,
                            fontWeight: FontWeight.w400,
                            fontSize: 14,
                            text:
                                widget.customerWalletBalance.toString() ?? '0',
                            imagePath: AppImages.nBlackCurrency,
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Hoppr wallet can only be used to pay for Rides and Packages on Hoppr",
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),

                      const SizedBox(height: 50),

                      Center(
                        child: TextField(
                          autofocus: true,
                          controller: _amountController,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: const InputDecoration(
                            hintText: "0",
                            border: InputBorder.none,
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CustomTextFields.textWithStylesSmall(
                            fontWeight: FontWeight.w400,
                            colors: AppColors.commonBlack,
                            'Minimum balance : ',
                            fontSize: 14,
                          ),
                          CustomTextFields.textWithImage(
                            colors: AppColors.commonBlack,
                            fontWeight: FontWeight.w400,
                            fontSize: 14,
                            text:
                                widget.minimumWalletAddBalance.toString() ??
                                '0',
                            imagePath: AppImages.nBlackCurrency,
                          ),
                        ],
                      ),

                      const SizedBox(height: 15),

                      // Quick add buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _quickAddButton(100),
                          const SizedBox(width: 10),
                          _quickAddButton(200),
                          const SizedBox(width: 10),
                          _quickAddButton(500),
                        ],
                      ),

                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
              SafeArea(
                child: Obx(() {
                  final data = controller.walletData.value;
                  if (controller.isLoading.value) {
                    return AppLoader.appLoader();
                  }
                  return AppButtons.button(
                    onTap:
                        controller.isLoading.value
                            ? null
                            : () async {
                              final text = _amountController.text.trim();

                              if (text.isEmpty) {
                                Get.snackbar("Error", "Please enter an amount");
                                return;
                              }

                              final double? amount = double.tryParse(text);
                              if (amount == null) {
                                Get.snackbar("Error", "Invalid amount entered");
                                return;
                              }
                              Get.to(
                                    () => WalletPaymentScreens(

                                  clientSecret: '',
                                  publishableKey: '',
                                  transactionId: '',

                                  amount: amount.toInt(),
                                ),
                              );
                              // controller.addWallet(
                              //   amount: amount,
                              //   method: 'STRIPE',
                              // );
                            },

                    text: 'Add Money',
                  );
                }),
              ),

              const SizedBox(height: 15),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickAddButton(int amount) {
    return OutlinedButton(
      onPressed: () {
        _amountController.text = amount.toString();
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
        side: const BorderSide(color: Colors.transparent),
        backgroundColor: AppColors.addMoney,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: Row(
        children: [
          Icon(Icons.add, color: AppColors.changeButtonColor),
          Text(
            "  $amount",
            style: TextStyle(color: AppColors.changeButtonColor),
          ),
        ],
      ),
    );
  }
}
