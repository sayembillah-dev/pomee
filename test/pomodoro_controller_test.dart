import 'package:flutter_test/flutter_test.dart';
import 'package:pomee/controllers/pomodoro_controller.dart';
import 'package:pomee/models/preset.dart';
import 'package:pomee/services/buzzer.dart';

class _FakeBuzzer extends Buzzer {
  bool chaos = false;
  int chimes = 0;

  @override
  Future<void> startChaos() async => chaos = true;
  @override
  Future<void> stopChaos() async => chaos = false;
  @override
  Future<void> chime() async => chimes++;
  @override
  void tick() {}
}

void main() {
  late DateTime now;
  late _FakeBuzzer buzzer;
  late PomodoroController c;
  var awake = false;

  setUp(() {
    now = DateTime(2026);
    buzzer = _FakeBuzzer();
    c = PomodoroController(
      buzzer: buzzer,
      now: () => now,
      keepAwake: (on) => awake = on,
      autoTick: false,
    );
  });

  test('starts idle on 25/5', () {
    expect(c.phase, Phase.idle);
    expect(c.remaining, const Duration(minutes: 25));
  });

  test('work → break → idle', () {
    c.toggle();
    expect(c.phase, Phase.work);
    expect(awake, isTrue);

    now = now.add(const Duration(minutes: 25));
    c.tick();
    expect(c.phase, Phase.rest);
    expect(c.remaining, const Duration(minutes: 5));

    now = now.add(const Duration(minutes: 5));
    c.tick();
    expect(c.phase, Phase.idle);
    expect(buzzer.chimes, 2);
    expect(awake, isFalse);
  });

  test('pause freezes remaining time', () {
    c.toggle();
    now = now.add(const Duration(minutes: 5));
    c.toggle();
    now = now.add(const Duration(minutes: 10));
    expect(c.remaining, const Duration(minutes: 20));
    c.toggle();
    now = now.add(const Duration(minutes: 1));
    expect(c.remaining, const Duration(minutes: 19));
  });

  test('picking up during work causes chaos only while held', () {
    c.toggle();
    c.setPickedUp(true);
    expect(c.chaos, isTrue);
    expect(buzzer.chaos, isTrue);
    c.setPickedUp(false);
    expect(c.chaos, isFalse);
    expect(buzzer.chaos, isFalse);
    expect(c.phase, Phase.work);
  });

  test('no chaos when idle, paused or on break', () {
    c.setPickedUp(true);
    expect(c.chaos, isFalse);
    c.setPickedUp(false);

    c.toggle();
    c.toggle(); // paused
    c.setPickedUp(true);
    expect(c.chaos, isFalse);
    c.setPickedUp(false);

    c.toggle();
    now = now.add(const Duration(minutes: 25));
    c.tick();
    c.setPickedUp(true);
    expect(c.chaos, isFalse);
  });

  test('choosing a time while idle selects it', () {
    expect(c.selectPreset(3), isTrue);
    expect(c.preset.workMinutes, 30);
    expect(c.remaining, const Duration(minutes: 30));
    c.toggle();
    now = now.add(const Duration(minutes: 30));
    c.tick();
    expect(c.remaining, const Duration(minutes: 7));
  });

  test('the time is locked while running, free once paused', () {
    c.toggle();
    now = now.add(const Duration(minutes: 3));
    expect(c.selectPreset(0), isFalse);
    expect(c.remaining, const Duration(minutes: 22));

    c.toggle(); // paused
    // The same time keeps the paused session.
    expect(c.selectPreset(defaultPreset), isTrue);
    expect(c.paused, isTrue);
    expect(c.remaining, const Duration(minutes: 22));

    // A new time ends it and readies the new length.
    expect(c.selectPreset(0), isTrue);
    expect(c.phase, Phase.idle);
    expect(c.remaining, const Duration(minutes: 10));
  });

  test('pausing a break also frees the time', () {
    c.toggle();
    now = now.add(const Duration(minutes: 25));
    c.tick(); // now on break
    c.toggle(); // paused
    expect(c.selectPreset(1), isTrue);
    expect(c.phase, Phase.idle);
    expect(c.remaining, const Duration(minutes: 20));
  });
}
