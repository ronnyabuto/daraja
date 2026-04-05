/// The B2C transaction type sent to Safaricom.
///
/// Determines how the payment is categorised in M-Pesa transaction history
/// and on the recipient's statement.
enum B2cCommandId {
  /// Standard business payment. Use for most disbursement use cases.
  businessPayment,

  /// Salary payment to employees.
  salaryPayment,

  /// Promotional payment (e.g. cashback, loyalty).
  promotionPayment;

  /// Returns the Safaricom API string for this command ID.
  String toApiString() => switch (this) {
    B2cCommandId.businessPayment => 'BusinessPayment',
    B2cCommandId.salaryPayment => 'SalaryPayment',
    B2cCommandId.promotionPayment => 'PromotionPayment',
  };
}
