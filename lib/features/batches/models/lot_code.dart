class LotCode {
  const LotCode({
    required this.dryerCode,
    required this.year,
    required this.julianDay,
    required this.productOfDay,
    required this.campaignNum,
  });

  final String dryerCode;
  final int year;
  final int julianDay;
  final String productOfDay;
  final int campaignNum;

  String get campaignCode {
    final day = julianDay.toString().padLeft(3, '0');
    return '$dryerCode$year$day$productOfDay-$campaignNum';
  }

  String sublotCode(int index) {
    final letter = String.fromCharCode('A'.codeUnitAt(0) + index);
    return '$campaignCode$letter';
  }

  static int julianDayFromDate(DateTime date) {
    final utcDate = DateTime.utc(date.year, date.month, date.day);
    final startOfYear = DateTime.utc(date.year, 1, 1);
    return utcDate.difference(startOfYear).inDays + 1;
  }
}
