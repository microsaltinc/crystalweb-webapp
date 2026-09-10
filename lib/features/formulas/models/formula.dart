class Formula {
  Formula({
    required this.id,
    required this.code,
    required this.description,
    required this.saltPct,
    this.process,
    required this.saltOrigin,
    required this.carrierOrigin,
    required this.iodine,
    required this.gmoStatus,
    this.additive,
    this.region,
    this.extraIngredients = const [],
    this.certificateOfOrigin,
    this.comment,
    required this.active,
    required this.createdAt,
    this.isTesting = false,
  });

  factory Formula.fromJson(Map<String, dynamic> json) {
    return Formula(
      id: json['id'] as String,
      code: json['code'] as String,
      description: json['description'] as String,
      saltPct: json['salt_pct'] as int,
      process: json['process'] as String?,
      saltOrigin: json['salt_origin'] as String,
      carrierOrigin: json['carrier_origin'] as String,
      iodine: json['iodine'] as String,
      gmoStatus: json['gmo_status'] as String,
      additive: json['additive'] as String?,
      region: json['region'] as String?,
      extraIngredients: (json['extra_ingredients'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      certificateOfOrigin: json['certificate_of_origin'] as String?,
      comment: json['comment'] as String?,
      active: json['active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      isTesting: json['is_testing'] as bool? ?? false,
    );
  }

  final String id;
  final String code;
  final String description;
  final int saltPct;
  final String? process;
  final String saltOrigin;
  final String carrierOrigin;
  final String iodine;
  final String gmoStatus;
  final String? additive;
  final String? region;
  final List<String> extraIngredients;
  final String? certificateOfOrigin;
  final String? comment;
  final bool active;
  final DateTime createdAt;
  final bool isTesting;

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'description': description,
        'salt_pct': saltPct,
        'process': process,
        'salt_origin': saltOrigin,
        'carrier_origin': carrierOrigin,
        'iodine': iodine,
        'gmo_status': gmoStatus,
        'additive': additive,
        'region': region,
        'extra_ingredients': extraIngredients,
        'certificate_of_origin': certificateOfOrigin,
        'comment': comment,
        'active': active,
        'created_at': createdAt.toIso8601String(),
        'is_testing': isTesting,
      };
}

/// Utility to build formula name codes and descriptions from segments.
class FormulaCodeBuilder {
  FormulaCodeBuilder._();

  static const saltOriginLabels = {
    'SS': 'Sea Salt',
    'MS': 'Mined Salt',
  };

  static const carrierOriginLabels = {
    'CN': 'Corn Maltodextrin',
    'TAS': 'Tapioca Starch',
    'TA': 'Tapioca Maltodextrin',
  };

  static const iodineLabels = {
    'IO': 'Iodized',
    'NI': 'Non-Iodized',
  };

  static const gmoStatusLabels = {
    'GM': 'GMO',
    'IP': 'non-GMO',
  };

  static const regionLabels = {
    'MX': 'Mexico',
    'CA': 'Canada',
  };

  static const validSaltPcts = [25, 50, 60, 75];

  /// Builds the dot-separated formula name code.
  ///
  /// Format: [Process].[Salt Origin].[Carrier Origin].[Iodine].[GMO].[Salt%][.Additive][.ExtraIng1][.ExtraIng2][-Region]
  static String buildCode({
    String? process,
    required String saltOrigin,
    required String carrierOrigin,
    required String iodine,
    required String gmoStatus,
    required int saltPct,
    String? additive,
    List<String> extraIngredients = const [],
    String? region,
  }) {
    final segments = <String>[];
    if (process != null) segments.add(process);
    segments.add(saltOrigin);
    segments.add(carrierOrigin);
    segments.add(iodine);
    segments.add(gmoStatus);
    segments.add(saltPct.toString());
    if (additive != null) segments.add(additive);
    final sorted = [...extraIngredients]..sort();
    segments.addAll(sorted);

    var code = segments.join('.');
    if (region != null) {
      code = '$code-$region';
    }
    return code;
  }

  /// Builds a human-readable description from segments.
  static String buildDescription({
    String? process,
    required String saltOrigin,
    required String carrierOrigin,
    required String iodine,
    required String gmoStatus,
    required int saltPct,
    String? additive,
    List<String> extraIngredients = const [],
    Map<String, String> extraIngredientLabels = const {},
    String? region,
  }) {
    final parts = <String>['Microsalt'];
    if (process == 'GR') parts.add('Granulated');
    parts.add(saltOriginLabels[saltOrigin] ?? saltOrigin);
    parts.add(iodineLabels[iodine] ?? iodine);
    parts.add(gmoStatusLabels[gmoStatus] ?? gmoStatus);
    parts.add(saltPct.toString());
    if (additive == 'MG') parts.add('Magnesium Stearate');
    final sortedExtras = [...extraIngredients]..sort();
    for (final code in sortedExtras) {
      parts.add('+ ${extraIngredientLabels[code] ?? code}');
    }

    var desc = parts.join(' ');
    if (region != null) {
      desc = '$desc - ${regionLabels[region] ?? region}';
    }
    return desc;
  }
}
