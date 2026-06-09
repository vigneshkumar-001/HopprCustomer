class ApiConsents {
  static const String baseUrl =
      'https://bk.myhoppr.com';
  static const String sharedBaseUrl =
      'https://bck.myhoppr.com';

  // static String baseUrl = 'https://q29l3cr9-5000.inc1.devtunnels.ms';
  // static String sharedBaseUrl = 'https://q29l3cr9-6000.inc1.devtunnels.ms';

  // static String baseUrl1 = 'https://4wsg7ghz-3000.inc1.devtunnels.ms';
  // static String baseUrl2 = 'https://q29l3cr9-4000.inc1.devtunnels.ms';

  // Hardcoded fallback — used only until the backend `gMapKey` is loaded.
  static const String _staticGoogleMapApiKey =
      'AIzaSyBjUSlWYV4spl2CeZ3ym32HqGROHwEACxk';

  // Dynamic Maps key from the backend (`gMapKey`), cached in memory.
  static String? _dynamicMapsKey;

  /// Key for ALL Google Maps HTTP calls (autocomplete, directions, geocoding,
  /// places) — works on iOS and Android. Uses the backend gMapKey when set,
  /// else the static fallback, so the key can be rotated server-side without an
  /// app update. (The native map-display key stays in the platform config.)
  static String get googleMapApiKey {
    final k = _dynamicMapsKey;
    return (k != null && k.trim().isNotEmpty)
        ? k.trim()
        : _staticGoogleMapApiKey;
  }

  /// Cache the backend gMapKey (call when app-settings / login returns it, and
  /// once at startup from storage).
  static void setDynamicMapsKey(String? key) {
    if (key != null && key.trim().isNotEmpty) {
      _dynamicMapsKey = key.trim();
    }
  }

  static final String createBooking = '$baseUrl/api/customer/create-booking';
  static final String fcmToken = '$baseUrl/api/customer/update-fcm-token';
  static final String userImageCaputre =
      '$baseUrl/api/customer/update-customer-booking-image';
  static final String confirmBooking =
      '$baseUrl/api/customer/parcel/confirm-booking';
  static final String sendDriverRequest =
      '$baseUrl/api/customer/send-driver-request';
  static final String paymentBooking = '$baseUrl/api/customer/paymentBooking';
  static final String activeBooking = '$baseUrl/api/customer/active-booking';

  /// Universal ride receipt (works for COD / Wallet / Paystack / Flutterwave).
  static String rideReceipt(String bookingId) =>
      '$baseUrl/api/customer/ride-receipt/$bookingId';

  static final String chatHistory = '$baseUrl/api/customer/chat-history';
  static final String rideHistory = '$baseUrl/api/customer/ride-history';
  static final String getCustomerDetails =
      '$baseUrl/api/customer/getCustomerDetails';
  static final String postCustomerDetails =
      '$baseUrl/api/customer/update-customer-settings';
  static final String addToWallet = '$baseUrl/api/customer/add-to-wallet';
  static final String getwalletBalance =
      '$baseUrl/api/customer/getwalletBalance';
  static final String customerWalletHistory =
      '$baseUrl/api/customer/customer-wallet-history';
  static final String signIn = '$baseUrl/api/customer/sign-in';
  static final String verifyOtp = '$baseUrl/api/customer/verify-otp';
  static final String resendOtp = '$baseUrl/api/customer/resend-otp';
  static final String logout = '$baseUrl/api/customer/logout';
  static final String notification = '$baseUrl/api/customer/notifications';
  static final String appSettings = '$baseUrl/api/settings/app-settings';
  static final String discountApply = '$baseUrl/api/customer/discount-apply';

  static final String sendDriverRequestStatus =
      '$baseUrl/api/customer/sendDriverRequestStatus';

  static final String addToWalletResponse =
      '$baseUrl/api/customer/add-to-wallet-reponse';
  // static String userImageUpload =
  //     'https://next.fenizotechnologies.com/Adrox/api/image-save';

  static final String userImageUpload = '$baseUrl/api/upload/image';

  // Support
  static final String supportCustomerTickets =
      '$baseUrl/api/support/customer/tickets';
  static final String supportCommonDetails = '$baseUrl/api/support/common-details';
  static final String supportMyTickets = '$baseUrl/api/support/my/tickets';

  static String driverSearch({
    required double pickupLat,
    required double pickupLng,
    required double dropLat,
    required double dropLng,
  }) {
    return Uri.parse('$baseUrl/api/customer/driver-search')
        .replace(
          queryParameters: {
            'latitude': '$pickupLat',
            'longitude': '$pickupLng',
            'dropLat': '$dropLat',
            'dropLng': '$dropLng',
          },
        )
        .toString();
  }

  static String cancelRide({required String bookingId}) {
    return '$baseUrl/api/customer/cancel-booking/${Uri.encodeComponent(bookingId)}';
  }

  static String rateDriver({required String bookingId}) {
    return '$baseUrl/api/customer/rate-driver/${Uri.encodeComponent(bookingId)}';
  }

  //Shared Url///
  static String driverSearchSharedBooking({
    required double pickupLat,
    required double pickupLng,
    required double dropLat,
    required double dropLng,
  }) {
    return Uri.parse('$sharedBaseUrl/api/shared/customer/driver-search')
        .replace(
          queryParameters: {
            'latitude': '$pickupLat',
            'longitude': '$pickupLng',
            'dropLat': '$dropLat',
            'dropLng': '$dropLng',
            'serviceType': 'Car',
            'sharedBooking': 'true',
          },
        )
        .toString();
  }

  static final String createSharedBooking =
      '$sharedBaseUrl/api/shared/customer/create-booking';

  static final String sharedSendRequest =
      '$sharedBaseUrl/api/shared/customer/send-driver-request';
  // https://hoppr-backend-3d2b7f783917.herokuapp.com/api/users/districts?state=$state
}
