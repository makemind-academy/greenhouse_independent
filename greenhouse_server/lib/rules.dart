import 'bus_link.dart';

/// A growing rule, written the way a grower talks.
///
/// "Open the vents when the house goes over 26." Note what the rule does NOT
/// say: it names
/// no probe, no relay, no model number. It speaks of a *kind* of reading and a
/// *kind* of actuator, so it survives the hardware being replaced underneath it.
///
/// This is the piece the domain expert owns. Everything else in the sample
/// exists to let this stay this short.
class Rule {
  const Rule({
    required this.name,
    required this.whenKind,
    required this.above,
    required this.thenKind,
    required this.setTo,
    required this.elseSetTo,
  });

  final String name;
  final String whenKind; // temperature | humidity | co2
  final double above; // in canonical units (C, pct, ppm)
  final String thenKind; // vent | valve
  final double setTo;
  final double elseSetTo;

  /// What this rule wants, given the readings the bus reported.
  ///
  /// Returns null when the greenhouse has nothing this rule can act on — an
  /// unattended rule is not an error. A grower may write a CO2 rule before the
  /// CO2 probe arrives, and that should simply do nothing until it does.
  RuleDecision? decide(List<BusNode> nodes) {
    final sensor = nodes.where((n) => n.isSensor && n.kind == whenKind);
    final actuator = nodes.where((n) => n.isActuator && n.kind == thenKind);
    if (sensor.isEmpty || actuator.isEmpty) return null;

    final reading = sensor.first.canonicalValue;
    final fired = reading > above;
    return RuleDecision(
      rule: this,
      sensorId: sensor.first.id,
      reading: reading,
      actuatorId: actuator.first.id,
      target: fired ? setTo : elseSetTo,
      fired: fired,
    );
  }
}

class RuleDecision {
  const RuleDecision({
    required this.rule,
    required this.sensorId,
    required this.reading,
    required this.actuatorId,
    required this.target,
    required this.fired,
  });

  final Rule rule;
  final String sensorId;
  final double reading;
  final String actuatorId;
  final double target;
  final bool fired;

  Map<String, dynamic> toJson() => {
        'rule': rule.name,
        'sensor': sensorId,
        'reading': double.parse(reading.toStringAsFixed(1)),
        'actuator': actuatorId,
        'target': target,
        'fired': fired,
      };
}

/// The house rules. Editing this list is the whole job of retuning a greenhouse
/// — no rebuild of the control side, no rewiring.
const houseRules = <Rule>[
  Rule(
    name: 'vent above 26C',
    whenKind: 'temperature',
    above: 26.0,
    thenKind: 'vent',
    setTo: 80.0,
    elseSetTo: 0.0,
  ),
  Rule(
    name: 'water below 60% humidity',
    whenKind: 'humidity',
    above: 60.0,
    thenKind: 'valve',
    setTo: 0.0,
    elseSetTo: 40.0,
  ),
];
