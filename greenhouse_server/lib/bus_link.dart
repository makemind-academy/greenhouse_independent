import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One node on the greenhouse bus, exactly as the node described itself.
///
/// Nothing here was looked up in a table upstream. `model` and `unit` are what
/// the hardware said it was, which is why swapping a probe for a different one
/// does not require editing anything on this side.
class BusNode {
  BusNode({
    required this.id,
    required this.role,
    required this.kind,
    required this.model,
    required this.unit,
    required this.value,
  });

  factory BusNode.fromJson(Map<String, dynamic> j) => BusNode(
        id: j['id'] as String,
        role: j['role'] as String,
        kind: j['kind'] as String,
        model: j['model'] as String,
        unit: j['unit'] as String,
        value: (j['value'] as num).toDouble(),
      );

  final String id;
  final String role; // sensor | actuator
  final String kind; // temperature | humidity | co2 | vent | valve
  final String model;
  final String unit;
  final double value;

  bool get isSensor => role == 'sensor';
  bool get isActuator => role == 'actuator';

  /// The reading in the unit the rules are written in.
  ///
  /// This is the only place in the sample that knows about units, and it works
  /// off what the node declared rather than off its model name. A probe nobody
  /// has heard of still reports its unit, so it still lands here correctly.
  double get canonicalValue {
    switch (unit) {
      case 'F':
        return (value - 32) * 5 / 9;
      default:
        return value;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'kind': kind,
        'model': model,
        'unit': unit,
        'value': value,
        'canonical': double.parse(canonicalValue.toStringAsFixed(1)),
      };
}

/// Host side of the greenhouse bus.
///
/// On a bench the far end is [greenhouse_bus] over a pipe. In a glasshouse it
/// is an RS-485 line or a wifi link to the relay boards; the message shape is
/// the same, so only the two lines that open the channel differ.
class BusLink {
  BusLink({this.requestTimeout = const Duration(seconds: 2)});

  final Duration requestTimeout;

  late final Process _proc;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  int _nextId = 1;

  final List<String> transcript = <String>[];

  Future<void> start(String executable, List<String> install) async {
    _proc = await Process.start(executable, install);
    _proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine);
    _proc.stderr.drain<void>();
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    transcript.add('<= $line');
    final reply = jsonDecode(line) as Map<String, dynamic>;
    _pending.remove(reply['id'] as int)?.complete(reply);
  }

  Future<Map<String, dynamic>> call(
    String tool, [
    Map<String, dynamic> args = const {},
  ]) async {
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    final request = jsonEncode({'id': id, 'tool': tool, 'args': args});
    transcript.add('=> $request');
    _proc.stdin.writeln(request);

    final reply = await completer.future.timeout(
      requestTimeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('bus did not answer $tool', requestTimeout);
      },
    );
    if (reply['ok'] != true) {
      throw StateError('bus refused $tool: ${reply['error']}');
    }
    return (reply['result'] as Map).cast<String, dynamic>();
  }

  /// Ask the bus what is installed. Called at startup and whenever the grower
  /// says something changed — never cached as if the greenhouse were fixed.
  Future<List<BusNode>> scan() async {
    final r = await call('bus.list');
    return (r['nodes'] as List)
        .map((n) => BusNode.fromJson((n as Map).cast<String, dynamic>()))
        .toList();
  }

  void dispose() => _proc.kill();
}
