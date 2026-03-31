import 'package:daraja/daraja.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the pre-initialized [Daraja] instance.
///
/// Override this in [ProviderScope] with the instance created in `main()`.
/// Recovery (`restorePendingPayment`) runs exactly once before `runApp`.
final darajaProvider = Provider<Daraja>((_) => throw UnimplementedError());
