import 'lib/domain/entities.dart';

void main() {
  // Test 1: clearTarget=true should clear target even if target param is provided
  const original = AppSettings(target: CustomSafFolder('u1', 'F1'));
  final result1 = original.copyWith(
    clearTarget: true,
    target: const CustomSafFolder('u2', 'F2'),
  );
  assert(
    result1.target == null,
    'clearTarget=true should override target param',
  );

  // Test 2: clearTarget=true with no target param
  const s2 = AppSettings(target: CustomSafFolder('u', 'F'));
  final r2 = s2.copyWith(clearTarget: true);
  assert(r2.target == null, 'clearTarget=true should set target to null');

  // Test 3: target param with clearTarget=false (default)
  const s3 = AppSettings();
  final r3 = s3.copyWith(target: const CustomSafFolder('u', 'F'));
  assert(
    r3.target?.uriString == 'u',
    'target param should set target when clearTarget=false',
  );

  // Test 4: no target param, clearTarget=false (default), should preserve
  const s4 = AppSettings(target: CustomSafFolder('original', 'F'));
  final r4 = s4.copyWith(createAuthorFolder: true);
  assert(
    r4.target?.uriString == 'original',
    'target should be preserved when not specified',
  );

  // ignore: avoid_print
  print('All copyWith logic tests passed!');
}
