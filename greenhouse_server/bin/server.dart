import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:greenhouse_server/bus_link.dart';
import 'package:greenhouse_server/rules.dart';
import 'package:greenhouse_server/screens.dart';
import 'package:mcp_server/mcp_server.dart';

/// greenhouse_server — keeps sensing and actuating apart.
///
///   greenhouse_bus (C) ──serial/RS-485──▶ THIS server ──MCP──▶ grower's screen
///     nodes describe themselves            asks what is there
///                                          applies rules written in kinds
///
/// The thing this server refuses to have is a table pairing probe X with relay
/// Y. It asks the bus what is installed, and the grower's rules name kinds of
/// readings rather than part numbers. That is what lets a probe be replaced
/// without a redevelopment project.
///
/// The installed set can be handed in on the command line so the same server
/// can be pointed at different greenhouses:
///
///   dart run bin/server.dart t1:temperature:FX-200:F v1:vent:VT-9
void main(List<String> args) async {
  // `--house=NAME` names the installation on screen; everything else on the
  // command line is the node list the bus should stand up.
  final house = args
      .firstWhere((a) => a.startsWith('--house='), orElse: () => '--house=1')
      .substring(8);
  final nodes = args.where((a) => !a.startsWith('--house=')).toList();

  final bus = BusLink();
  await bus.start('../greenhouse_bus/greenhouse_bus', nodes);

  const config = McpServerConfig(
    name: 'Greenhouse Server',
    version: '1.0.0',
    capabilities: ServerCapabilities(
      tools: ToolsCapability(listChanged: true),
      resources: ResourcesCapability(listChanged: true),
    ),
  );

  final server = McpServer.createServer(config);
  final greenhouse = GreenhouseServer(server, bus, house);

  // Register the surface BEFORE accepting a connection, and before the first
  // bus scan. Scanning is a round trip to the hardware; a client that connects
  // during it would otherwise ask for `ui://grower` and be told it does not
  // exist. Nothing the client can ask for may depend on the greenhouse having
  // answered yet.
  greenhouse.register();

  final transport = McpServer.createStdioTransport().get();
  server.connect(transport);

  // Now find out what is actually installed.
  await greenhouse.warmUp();

  await Completer<void>().future;
}

class GreenhouseServer {
  GreenhouseServer(this.server, this.bus, this.house);

  final Server server;
  final String house;
  final BusLink bus;

  List<BusNode> _nodes = const [];
  String _notice = '';
  /// One line per rule that acted, in the order it acted. A joined string
  /// would read the same on this screen and be unsplittable on the next one.
  List<String> _ruleLog = const [];

  /// Publish the screen and the tools. Synchronous on purpose — see main().
  void register() {
    _registerScreen();
    _registerTools();
  }

  /// First look at the hardware. Anything asked for before this finishes gets
  /// an empty node list, which is the truth at that moment rather than an error.
  Future<void> warmUp() async {
    _nodes = await bus.scan();
    _notice = 'Scanned ${_nodes.length} nodes at startup';
  }

  void _registerScreen() {
    const documents = <String, (String, String, Map<String, dynamic>)>{
      'ui://app': ('Greenhouse', 'Routes and the house\'s theme',
          applicationDefinition),
      'ui://app/info': ('App Info', 'Lightweight metadata (spec 11.6)',
          appInfoDefinition),
      'ui://pages/grower': ('Greenhouse', 'What is on the bus right now',
          growerDefinition),
    };
    documents.forEach((uri, spec) {
      final (name, description, document) = spec;
      server.addResource(
        uri: uri,
        name: name,
        description: description,
        mimeType: 'application/json',
        handler: (requestedUri, params) async => ReadResourceResult(
          contents: [
            ResourceContentInfo(
              uri: requestedUri,
              mimeType: 'application/json',
              text: jsonEncode(document),
            ),
          ],
        ),
      );
    });
  }

  void _registerTools() {
    // Ask the bus again. A greenhouse is not a fixed installation — a probe
    // dies, a grower adds a CO2 sensor mid-season. Rescanning is a normal
    // operation, not a maintenance event.
    server.addTool(
      name: 'bus.rescan',
      description: 'Ask the bus what is installed right now',
      inputSchema: const {'type': 'object', 'properties': {}},
      handler: (args) async {
        final before = _nodes.map((n) => n.id).toSet();
        _nodes = await bus.scan();
        final after = _nodes.map((n) => n.id).toSet();
        final added = after.difference(before);
        final gone = before.difference(after);
        _notice = 'Rescanned: ${_nodes.length} nodes'
            '${added.isEmpty ? '' : ' · added ${added.join(",")}'}'
            '${gone.isEmpty ? '' : ' · gone ${gone.join(",")}'}';
        return _state();
      },
    );

    // Read every sensor and let each rule decide. The rules never learn which
    // model answered — they get a reading in canonical units and a kind.
    server.addTool(
      name: 'rules.apply',
      description: 'Evaluate the house rules against current readings and drive the actuators',
      inputSchema: const {'type': 'object', 'properties': {}},
      handler: (args) async {
        _nodes = await bus.scan();

        final applied = <Map<String, dynamic>>[];
        final skipped = <String>[];
        for (final rule in houseRules) {
          final decision = rule.decide(_nodes);
          if (decision == null) {
            // Nothing installed for this rule to work with. Say so rather than
            // silently doing nothing — a grower needs to know a rule is idle.
            skipped.add(rule.name);
            continue;
          }
          await bus.call('node.set', {
            'node': decision.actuatorId,
            'value': decision.target,
          });
          applied.add(decision.toJson());
          stderr.writeln('[rule] ${decision.rule.name} '
              'sensor=${decision.sensorId} reading=${decision.reading.toStringAsFixed(1)} '
              'fired=${decision.fired} -> ${decision.actuatorId}=${decision.target}');
        }

        _nodes = await bus.scan();
        _ruleLog = applied
            .map((a) =>
                '${a['rule']}: ${a['reading']} -> ${a['actuator']}=${a['target']}')
            .toList();
        _notice = skipped.isEmpty
            ? '${applied.length} rules applied'
            : '${applied.length} applied · idle: ${skipped.join(", ")}';
        return _state();
      },
    );

    server.addTool(
      name: 'bus.state',
      description: 'Current node readings without changing anything',
      inputSchema: const {'type': 'object', 'properties': {}},
      handler: (args) async {
        _nodes = await bus.scan();
        return _state();
      },
    );

    // The raw lines, for the write-up. A claim about a bus is worth less than
    // the bytes that crossed it.
    server.addTool(
      name: 'bus.transcript',
      description: 'Raw request/reply lines exchanged with the bus',
      inputSchema: const {'type': 'object', 'properties': {}},
      handler: (args) async => CallToolResult(
        content: [TextContent(text: jsonEncode({'lines': bus.transcript}))],
      ),
    );
  }

  CallToolResult _state() {
    final sensors = _nodes.where((n) => n.isSensor).toList();
    final actuators = _nodes.where((n) => n.isActuator).toList();
    final install = sensors
        .where((n) => n.kind == 'temperature')
        .map((n) => '${n.model} (${n.unit})')
        .join(', ');

    final snapshot = {
      'nodes': _nodes.map((n) => n.toJson()).toList(),
      'sensorCount': sensors.length,
      'actuatorCount': actuators.length,
      'install': install.isEmpty ? 'no temperature probe' : install,
      'houseLabel': 'HOUSE $house · WHAT IS ON THE BUS',
      'notice': _notice,
      'ruleLog': _ruleLog,
      // The rule the house runs by when nobody is watching. It belongs with
      // the rules, not on the screen that happens to be showing them.
      'houseRule': 'The house runs its own rules on the bus · this screen is '
          'a window, not the controller',
    };
    return CallToolResult(content: [TextContent(text: jsonEncode(snapshot))]);
  }
}
