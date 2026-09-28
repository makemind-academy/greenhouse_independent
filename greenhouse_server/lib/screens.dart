/// The grower's screen.
///
/// The greenhouse is a bus with nodes on it: probes that answer and vents that
/// obey. Which nodes are present is discovered, not configured, so the screen
/// draws the list it is given rather than a layout somebody typed for this
/// particular house.
///
/// It is an `application` with one route: the colours belong to the house and
/// are declared once, so a second screen (the packhouse, a phone in a pocket)
/// inherits them.
library;

const _ink = '{{theme.color.onSurface}}';
const _muted = '{{theme.color.onSurfaceVariant}}';
const _accent = '{{theme.color.primary}}';
const _hair = '{{theme.color.outline}}';
const _surface = '{{theme.color.surface}}';
const _canvas = '{{theme.color.surfaceContainerHighest}}';
const _warn = '{{theme.color.warning}}';
const _mono = 'JetBrainsMono';

const Map<String, dynamic> _houseTheme = {
  'mode': 'light',
  'color': {
    'primary': '#2f7d4f',
    'onPrimary': '#ffffff',
    'primaryContainer': '#dcefe1',
    'onPrimaryContainer': '#0d3319',
    'surface': '#ffffff',
    'onSurface': '#121a15',
    'surfaceContainerHighest': '#f2f6f3',
    'onSurfaceVariant': '#7c8a80',
    'outline': '#e2eae5',
    'outlineVariant': '#eef3f0',
    'error': '#b3261e',
    'onError': '#ffffff',
    'warning': '#a4620a',
    'onWarning': '#ffffff',
    'inverseSurface': '#121a15',
    'inverseOnSurface': '#f2f6f3',
  },
  'spacing': {
    'xxs': 2, 'xs': 4, 'sm': 8, 'md': 16, 'lg': 24, 'xl': 32, '2xl': 48,
  },
  'shape': {
    'none': 0, 'extraSmall': 4, 'small': 8, 'medium': 12, 'large': 16,
    'extraLarge': 28, 'full': 999,
  },
  'fonts': {
    'JetBrainsMono': {'source': 'asset', 'family': 'JetBrainsMono'},
  },
};

const Map<String, dynamic> _initialState = {
  'nodes': <dynamic>[],
  'sensorCount': 0,
  'actuatorCount': 0,
  'install': '',
  'ruleLog': <dynamic>[],
  'houseRule': '',
  'houseLabel': 'WHAT IS ON THE BUS',
  'notice': '',
};

const Map<String, dynamic> applicationDefinition = {
  'type': 'application',
  'version': '1.3',
  'id': 'greenhouse.grower',
  'title': 'Greenhouse',
  'description': 'What is on the bus, and what the rules did about it.',
  'theme': _houseTheme,
  'initialRoute': '/grower',
  'routes': {'/grower': 'ui://pages/grower'},
  'state': {'initial': _initialState},
};

const Map<String, dynamic> appInfoDefinition = {
  'id': 'greenhouse.grower',
  'title': 'Greenhouse',
  'description': 'What is on the bus, and what the rules did about it.',
  'version': '1.0.0',
  'publisher': {'name': 'Grower'},
};

const Map<String, dynamic> growerDefinition = {
  'type': 'page',
  'metadata': {'title': 'Greenhouse'},
  'onInit': {'type': 'tool', 'tool': 'bus.state', 'params': {}},
  'state': {'initial': _initialState},
  'content': {
    'type': 'container',
    'decoration': {'color': _canvas},
    'child': {
      'type': 'linear',
      'direction': 'vertical',
      'crossAxisAlignment': 'stretch',
      'children': [
        {
          'type': 'container',
          'padding': {'left': 22, 'right': 22, 'top': 20, 'bottom': 16},
          'decoration': {
            'color': _surface,
            'border': {'bottom': true, 'color': _hair, 'width': 1},
          },
          'child': {
            'type': 'linear',
            'direction': 'horizontal',
            'crossAxisAlignment': 'center',
            'children': [
              {
                'type': 'linear',
                'direction': 'vertical',
                'gap': 4,
                'children': [
                  {
                    'type': 'text',
                    'content': '{{houseLabel}}',
                    'style': {
                      'fontSize': 12,
                      'color': _muted,
                      'letterSpacing': 2.0
                    },
                  },
                  {
                    'type': 'text',
                    'content': '{{install}}',
                    'style': {
                      'fontSize': 20,
                      'fontWeight': 'bold',
                      'color': _ink
                    },
                  },
                ],
              },
              {'type': 'spacer'},
              {
                'type': 'linear',
                'direction': 'vertical',
                'gap': 4,
                'crossAxisAlignment': 'end',
                'children': [
                  {
                    'type': 'text',
                    'content': 'NODES',
                    'style': {
                      'fontSize': 11,
                      'color': _muted,
                      'letterSpacing': 1.6
                    },
                  },
                  {
                    'type': 'text',
                    'content': '{{sensorCount}} probes · {{actuatorCount}} vents',
                    'style': {
                      'fontSize': 15,
                      'fontFamily': _mono,
                      'color': _ink
                    },
                  },
                ],
              },
            ],
          },
        },
        // Controls the reader presses in the player.
        {'type': 'container', 'padding': {'left': 22, 'right': 22, 'top': 10, 'bottom': 4}, 'child': {'type': 'linear', 'direction': 'horizontal', 'crossAxisAlignment': 'center', 'children': [{'type': 'button', 'label': 'Rescan the bus', 'variant': 'outlined', 'onTap': {'type': 'tool', 'tool': 'bus.rescan', 'params': {}}}, {'type': 'box', 'width': 10}, {'type': 'button', 'label': 'Apply the rules', 'variant': 'filled', 'onTap': {'type': 'tool', 'tool': 'rules.apply', 'params': {}}}]}},
        // The nodes as the bus reported them. A house with one more probe
        // draws one more row, and nobody edits a screen for it.
        {
          'type': 'expanded',
          'child': {
            'type': 'container',
            'padding': {'left': 22, 'right': 22, 'top': 16, 'bottom': 8},
            'child': {
              'type': 'container',
              'padding': {'all': 18},
              'decoration': {
                'color': _surface,
                'borderRadius': 14,
                'border': {'color': _hair, 'width': 1},
              },
              'child': {
                'type': 'list',
                'items': '{{nodes}}',
                'shrinkWrap': true,
                'itemSpacing': 10,
                'emptyMessage': 'Nothing answering on the bus',
                'itemTemplate': {
                  'type': 'linear',
                  'direction': 'horizontal',
                  'crossAxisAlignment': 'center',
                  'children': [
                    {
                      'type': 'text',
                      'content': '{{item.id}}',
                      'style': {
                        'fontSize': 14,
                        'fontFamily': _mono,
                        'color': _accent
                      },
                    },
                    {
                      'type': 'expanded',
                      'child': {
                        'type': 'container',
                        'padding': {'left': 16},
                        'child': {
                          'type': 'text',
                          'content': '{{item.model}}',
                          'style': {'fontSize': 16, 'color': _ink},
                        },
                      },
                    },
                    {
                      'type': 'text',
                      'content': '{{item.kind}}',
                      'style': {'fontSize': 13, 'color': _muted},
                    },
                    {
                      'type': 'container',
                      'padding': {'left': 18},
                      'child': {
                        'type': 'text',
                        'content': '{{item.value}} {{item.unit}}',
                        'style': {
                          'fontSize': 16,
                          'fontFamily': _mono,
                          'color': _ink
                        },
                      },
                    },
                  ],
                },
              },
            },
          },
        },
        // What the rules did, in the order they did it. The house keeps
        // running when nobody is looking, and this is the record of that.
        {
          'type': 'container',
          'padding': {'left': 22, 'right': 22, 'top': 0, 'bottom': 8},
          'child': {
            'type': 'container',
            'padding': {'all': 18},
            'decoration': {
              'color': _surface,
              'borderRadius': 14,
              'border': {'color': _hair, 'width': 1},
            },
            'child': {
              'type': 'linear',
              'direction': 'vertical',
              'gap': 8,
              'crossAxisAlignment': 'stretch',
              'children': [
                {
                  'type': 'text',
                  'content': 'WHAT THE RULES DID',
                  'style': {
                    'fontSize': 11,
                    'color': _muted,
                    'letterSpacing': 1.6
                  },
                },
                {
                  'type': 'list',
                  'items': '{{ruleLog}}',
                  'shrinkWrap': true,
                  'itemSpacing': 6,
                  'emptyMessage': 'No rule has fired yet',
                  'itemTemplate': {
                    'type': 'text',
                    'content': '{{item}}',
                    'style': {
                      'fontSize': 13,
                      'fontFamily': _mono,
                      'color': _ink
                    },
                  },
                },
              ],
            },
          },
        },
        {
          'type': 'container',
          'padding': {'left': 22, 'right': 22, 'top': 4, 'bottom': 18},
          'child': {
            'type': 'linear',
            'direction': 'horizontal',
            'crossAxisAlignment': 'center',
            'children': [
              {
                'type': 'expanded',
                'child': {
                  'type': 'text',
                  'content': '{{houseRule}}',
                  'style': {'fontSize': 13, 'color': _muted},
                },
              },
              {
                'type': 'text',
                'content': '{{notice}}',
                'style': {'fontSize': 13, 'color': _warn},
              },
            ],
          },
        },
      ],
    },
  },
};
