.PHONY: get format analyze test check

get:
	flutter pub get

format:
	dart format .

analyze:
	flutter analyze

test:
	flutter test

check:
	dart run tool/check.dart
