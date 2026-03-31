import 'chama_member.dart';

class ChamaSession {
  const ChamaSession({
    required this.title,
    required this.totalAmount,
    required this.members,
  });

  final String title;
  final int totalAmount;
  final List<ChamaMember> members;

  int get sharePerMember => totalAmount ~/ members.length;

  int get memberCount => members.length;
}
