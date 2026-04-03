import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hopper/Core/Utility/app_images.dart';

class AppLoader {
  static Widget appLoader({double? imgHeight = 70, double? imgWeight = 70}) {
    return Image.asset(
      AppImages.ladingAnimation,
      fit: BoxFit.contain,
      height: imgHeight,
      width: imgWeight,
    );
  }

  static circularLoader() {
    return Center(child: CupertinoActivityIndicator(radius: 14));
  }
}
