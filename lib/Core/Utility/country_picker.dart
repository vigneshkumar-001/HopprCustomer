import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:hopper/Presentation/Drawer/controller/profle_cotroller.dart';
class CountryPicker {
  void showCountrySelector(BuildContext context, ProfleCotroller controller) {
    showCountryPicker(
      context: context,
      showSearch: true,
      showPhoneCode: true,
      searchAutofocus: true,
      countryListTheme: CountryListThemeData(
        flagSize: 22,
        backgroundColor: Colors.white,
        bottomSheetHeight: 600,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30.0),
          topRight: Radius.circular(30.0),
        ),
        searchTextStyle: TextStyle(color: Colors.black),
        inputDecoration: InputDecoration(
          hintText: 'Search',
          hintStyle: TextStyle(color: Colors.grey),
          prefixIcon: Icon(Icons.search, color: Colors.black),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.black),
            borderRadius: BorderRadius.circular(8),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.black, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
      onSelect: (Country country) {
        controller.setSelectedCountry(country);
      },
    );
  }
}

