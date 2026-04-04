import 'package:daraja/daraja.dart';

enum MemberStatus {
  idle,
  initiating,
  pending,
  success,
  failed,
  cancelled,
  timeout,
  error,
}

MemberStatus statusFromState(PaymentState state) => switch (state) {
  PaymentIdle() => MemberStatus.idle,
  PaymentInitiating() => MemberStatus.initiating,
  PaymentPending() => MemberStatus.pending,
  PaymentSuccess() => MemberStatus.success,
  PaymentFailed() => MemberStatus.failed,
  PaymentCancelled() => MemberStatus.cancelled,
  PaymentTimeout() => MemberStatus.timeout,
  PaymentError() => MemberStatus.error,
};

class ChamaMember {
  const ChamaMember({
    required this.id,
    required this.name,
    required this.phone,
    required this.userId,
  });

  final String id;
  final String name;
  final String phone;
  final String userId;
}
