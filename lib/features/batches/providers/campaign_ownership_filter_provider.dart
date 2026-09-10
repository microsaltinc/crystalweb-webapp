import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../operators/models/operator.dart';

enum OwnershipFilterKind { all, mine, unassigned, specificOwner }

class OwnershipFilter {
  const OwnershipFilter._(this.kind, {this.operatorId});

  const OwnershipFilter.all() : this._(OwnershipFilterKind.all);
  const OwnershipFilter.mine() : this._(OwnershipFilterKind.mine);
  const OwnershipFilter.unassigned() : this._(OwnershipFilterKind.unassigned);
  const OwnershipFilter.specificOwner(String operatorId)
    : this._(OwnershipFilterKind.specificOwner, operatorId: operatorId);

  final OwnershipFilterKind kind;
  final String? operatorId;

  String get queryValue => switch (kind) {
    OwnershipFilterKind.all => 'all',
    OwnershipFilterKind.mine => 'mine',
    OwnershipFilterKind.unassigned => 'unassigned',
    OwnershipFilterKind.specificOwner => operatorId ?? 'all',
  };

  String label(List<Operator> operators) {
    return switch (kind) {
      OwnershipFilterKind.all => 'All',
      OwnershipFilterKind.mine => 'Mine',
      OwnershipFilterKind.unassigned => 'Unassigned',
      OwnershipFilterKind.specificOwner => _specificOwnerLabel(operators),
    };
  }

  String _specificOwnerLabel(List<Operator> operators) {
    final id = operatorId;
    if (id == null) return 'Owner';
    for (final operator in operators) {
      if (operator.id == id) return operator.ownershipLabel;
    }
    return 'Owner';
  }
}

final campaignOwnershipFilterProvider =
    StateProvider.autoDispose<OwnershipFilter>((ref) {
      return const OwnershipFilter.all();
    });
