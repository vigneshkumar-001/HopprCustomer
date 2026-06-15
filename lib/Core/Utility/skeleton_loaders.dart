import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'package:hopper/Core/Consents/app_colors.dart';

/// Layout-matched shimmer skeletons used while a screen's data loads.
/// Each builder mirrors the real card so the loading state has the same shape
/// as the loaded content (no jarring spinner -> list jump).
class SkeletonLoaders {
  SkeletonLoaders._();

  // ----------------------------- RIDE HISTORY -----------------------------
  static Widget rideHistory({int items = 6}) {
    return Skeletonizer(
      enabled: true,
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        itemCount: items,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _box(64, 64, radius: 16),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Drop address placeholder line',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text('Driver name', style: TextStyle(fontSize: 12.5)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '0000.00',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
                const SizedBox(height: 10),
                Row(
                  children: const [
                    Text('00th Mon 0000 • 00:00 AM',
                        style: TextStyle(fontSize: 12)),
                    Spacer(),
                    Text('  Status  ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        )),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------- NOTIFICATIONS ----------------------------
  static Widget notifications({int items = 7}) {
    return Skeletonizer(
      enabled: true,
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(10),
        itemCount: items,
        itemBuilder: (_, __) => Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.rideShareContainerColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(radius: 18),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Notification title placeholder',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            )),
                        SizedBox(height: 4),
                        Text('Notification description line here',
                            style: TextStyle(fontSize: 12)),
                        SizedBox(height: 4),
                        Text('ID: 000000', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('00th Mon 0000 • 00:00 AM',
                  style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------- SUPPORT --------------------------------
  static Widget support({int items = 6}) {
    return Skeletonizer(
      enabled: true,
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        itemCount: items,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE4E7EC)),
          ),
          child: Row(
            children: [
              _box(54, 54, radius: 14),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Support ticket subject placeholder line',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        )),
                    SizedBox(height: 6),
                    Text('Created on 00 Mon 0000',
                        style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------- WALLET HISTORY -----------------------------
  /// Returns a non-scrollable column of transaction rows — designed to sit
  /// inside the Wallet screen's existing parent ListView (below the balance
  /// card), so only the history portion shows as skeletons.
  static Widget walletHistory({int items = 6}) {
    return Skeletonizer(
      enabled: true,
      child: Column(
        children: List.generate(
          items,
          (_) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.commonWhite,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const CircleAvatar(radius: 22),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Transaction title',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          )),
                      SizedBox(height: 4),
                      Text('Description line', style: TextStyle(fontSize: 12)),
                      SizedBox(height: 4),
                      Text('00th Mon 0000', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('0000.00',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        )),
                    SizedBox(height: 4),
                    Text('wallet', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------- PARCEL HISTORY ---------------------------
  static Widget parcelHistory({int items = 5}) {
    return Skeletonizer(
      enabled: true,
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        itemCount: items,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.rideShareContainerColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Text('Parcel type',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      )),
                  Spacer(),
                  Text('  Completed  ',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 10),
              const Text('FROM NAME  ->  TO NAME',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 14),
              Row(
                children: [
                  _box(12, 12, radius: 6),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Pickup address placeholder line here',
                        style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _box(12, 12, radius: 6),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Delivery address placeholder line here',
                        style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: const [
                  Text('0.0', style: TextStyle(fontSize: 13)),
                  Spacer(),
                  Text('0000.00',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      )),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------- HOME BANNER -------------------------------
  /// Skeleton for the home promo banner carousel (matches the 160px rounded
  /// image card + tagline) so it doesn't pop in suddenly after loading.
  static Widget homeBanner() {
    return Skeletonizer(
      enabled: true,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 2.0,
            child: _box(double.infinity, double.infinity, radius: 18),
          ),
          const SizedBox(height: 14),
          const Text(
            'Book and move, anywhere in the city',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 2.3,
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  // --------------------------- BOOK RIDE CARS -----------------------------
  /// Skeleton for the book-ride vehicle list (Luxury / Sedan cards).
  static Widget bookRideCars({int items = 2}) {
    return Skeletonizer(
      enabled: true,
      child: Column(
        children: List.generate(
          items,
          (i) => Padding(
            padding: EdgeInsets.only(bottom: i == items - 1 ? 0 : 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.black.withOpacity(0.06)),
              ),
              child: ListTile(
                leading: _box(65, 32, radius: 6),
                title: Row(
                  children: const [
                    Text('Car type',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    Spacer(),
                    Text('0000.00',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                subtitle: Row(
                  children: const [
                    Text('Comfy, Economical Cars'),
                    Spacer(),
                    Text('0 min'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------- helpers --------------------------------
  static Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }

  static Widget _box(double w, double h, {double radius = 12}) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
