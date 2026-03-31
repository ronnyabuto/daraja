class PotState {
  const PotState({
    required this.collected,
    required this.target,
    required this.paidCount,
    required this.memberCount,
  });

  const PotState.empty({required this.target, required this.memberCount})
      : collected = 0,
        paidCount = 0;

  final int collected;
  final int target;
  final int paidCount;
  final int memberCount;

  bool get isComplete => paidCount >= memberCount;

  double get progress => target == 0 ? 0 : collected / target;

  PotState withPayment(int amount) => PotState(
        collected: collected + amount,
        target: target,
        paidCount: paidCount + 1,
        memberCount: memberCount,
      );
}
