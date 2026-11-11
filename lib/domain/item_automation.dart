part of 'models.dart';

class ItemAutomation {
  final bool completeExpired, deleteCompleted, deleteExpired;
  const ItemAutomation({
    this.completeExpired = false,
    this.deleteCompleted = false,
    this.deleteExpired = false,
  });
  ItemAutomation copyWith({
    bool? completeExpired,
    bool? deleteCompleted,
    bool? deleteExpired,
  }) => ItemAutomation(
    completeExpired: completeExpired ?? this.completeExpired,
    deleteCompleted: deleteCompleted ?? this.deleteCompleted,
    deleteExpired: deleteExpired ?? this.deleteExpired,
  );
  Map<String, dynamic> toJson() => {
    'completeExpired': completeExpired,
    'deleteCompleted': deleteCompleted,
    'deleteExpired': deleteExpired,
  };
  factory ItemAutomation.fromJson(Map<String, dynamic>? json) => ItemAutomation(
    completeExpired: json?['completeExpired'] == true,
    deleteCompleted: json?['deleteCompleted'] == true,
    deleteExpired: json?['deleteExpired'] == true,
  );
}
