/*
 * greenhouse_bus — the sensor/actuator side of a greenhouse, as a program.
 *
 * Stands in for the boards actually bolted to a glasshouse: a couple of sensor
 * nodes on a bus and a couple of relay nodes driving vents and a water valve.
 * It really compiles and really runs; what it does not have is glass and soil.
 *
 * The one idea it exists to demonstrate
 * -------------------------------------
 * A node DECLARES ITSELF. Ask the bus what is installed and every node answers
 * with its own id, kind, model and unit:
 *
 *     {"id":"t1","role":"sensor","kind":"temperature","model":"TH-100","unit":"C"}
 *
 * Nothing upstream keeps a table of which sensor is wired to which relay. That
 * table is exactly what makes a greenhouse controller expensive to change: swap
 * a temperature probe for a different model and the hardcoded pairing has to be
 * reworked. Here the upstream asks, and adapts to the answer.
 *
 * To show that, the installed set is not baked in either — it comes from argv:
 *
 *     ./greenhouse_bus t1:temperature:TH-100:C h1:humidity:HM-20:pct \
 *                      v1:vent:VT-9 w1:valve:WV-3
 *
 * Run it once with a Celsius probe and again with a Fahrenheit one and watch
 * how much of the rest has to change. (None of it.)
 *
 * Wire format: one JSON request per line in, one JSON reply per line out.
 *
 * Build: cc -O2 -o greenhouse_bus greenhouse_bus.c -lm
 */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define LINE_MAX_LEN 4096
#define MAX_NODES 16

typedef struct {
    char id[24];
    char role[16];  /* "sensor" or "actuator" */
    char kind[24];  /* temperature | humidity | co2 | vent | valve */
    char model[24];
    char unit[8];   /* sensors only: C | F | pct | ppm */
    double value;   /* sensors: reading. actuators: 0..100 open/flow */
} Node;

static Node g_nodes[MAX_NODES];
static int g_node_count = 0;
static double g_start_seconds = 0;

static double now_seconds(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static Node *find_node(const char *id) {
    for (int i = 0; i < g_node_count; i++) {
        if (strcmp(g_nodes[i].id, id) == 0) return &g_nodes[i];
    }
    return NULL;
}

/* The glasshouse warms through the morning and the vents cool it back down.
 * Sensors report in whatever unit the node was built for — the point is that
 * the number leaving here is honest to the hardware, not pre-converted for
 * anybody's convenience. */
static void tick_environment(void) {
    double t = now_seconds() - g_start_seconds;

    double vent_open = 0;
    for (int i = 0; i < g_node_count; i++) {
        if (strcmp(g_nodes[i].kind, "vent") == 0) vent_open = g_nodes[i].value;
    }

    /* Base climb, minus whatever the vents are bleeding off.
     *
     * The time constant is 5 s, not the half hour a real glasshouse takes to
     * warm through. A morning is compressed so that a run of the sample crosses
     * the vent threshold while you are watching it. Everything else about the
     * curve — approach rather than jump, vents subtracting rather than
     * resetting — is the shape of the real thing. */
    double celsius = 21.0 + 11.0 * (1.0 - exp(-t / 5.0)) - (vent_open / 100.0) * 7.0;

    for (int i = 0; i < g_node_count; i++) {
        Node *n = &g_nodes[i];
        if (strcmp(n->role, "sensor") != 0) continue;
        if (strcmp(n->kind, "temperature") == 0) {
            n->value = (strcmp(n->unit, "F") == 0) ? celsius * 9.0 / 5.0 + 32.0
                                                   : celsius;
        } else if (strcmp(n->kind, "humidity") == 0) {
            n->value = 72.0 - (celsius - 21.0) * 1.8;
        } else if (strcmp(n->kind, "co2") == 0) {
            n->value = 640.0 - (vent_open / 100.0) * 180.0;
        }
    }
}

static int json_str(const char *src, const char *key, char *out, size_t cap) {
    char pat[64];
    snprintf(pat, sizeof(pat), "\"%s\"", key);
    const char *p = strstr(src, pat);
    if (!p) return 0;
    p = strchr(p + strlen(pat), ':');
    if (!p) return 0;
    while (*p && *p != '"') p++;
    if (*p != '"') return 0;
    p++;
    size_t n = 0;
    while (*p && *p != '"' && n + 1 < cap) out[n++] = *p++;
    out[n] = '\0';
    return 1;
}

static int json_num(const char *src, const char *key, double *out) {
    char pat[64];
    snprintf(pat, sizeof(pat), "\"%s\"", key);
    const char *p = strstr(src, pat);
    if (!p) return 0;
    p = strchr(p + strlen(pat), ':');
    if (!p) return 0;
    p++;
    while (*p == ' ') p++;
    char *end = NULL;
    double v = strtod(p, &end);
    if (end == p) return 0;
    *out = v;
    return 1;
}

/* argv entry -> node. sensors: id:kind:model:unit   actuators: id:kind:model */
static int add_node_from_spec(const char *spec) {
    if (g_node_count >= MAX_NODES) return 0;
    char buf[128];
    snprintf(buf, sizeof(buf), "%s", spec);

    char *parts[4] = {NULL, NULL, NULL, NULL};
    int count = 0;
    for (char *tok = strtok(buf, ":"); tok && count < 4; tok = strtok(NULL, ":")) {
        parts[count++] = tok;
    }
    if (count < 3) return 0;

    Node *n = &g_nodes[g_node_count++];
    memset(n, 0, sizeof(*n));
    snprintf(n->id, sizeof(n->id), "%s", parts[0]);
    snprintf(n->kind, sizeof(n->kind), "%s", parts[1]);
    snprintf(n->model, sizeof(n->model), "%s", parts[2]);

    int is_actuator = (strcmp(n->kind, "vent") == 0 || strcmp(n->kind, "valve") == 0);
    snprintf(n->role, sizeof(n->role), "%s", is_actuator ? "actuator" : "sensor");
    snprintf(n->unit, sizeof(n->unit), "%s", count >= 4 ? parts[3] : "pct");
    n->value = is_actuator ? 0.0 : 0.0;
    return 1;
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IOLBF, 0);
    g_start_seconds = now_seconds();

    for (int i = 1; i < argc; i++) add_node_from_spec(argv[i]);
    if (g_node_count == 0) {
        /* A plain default install so the sample runs with no arguments. */
        add_node_from_spec("t1:temperature:TH-100:C");
        add_node_from_spec("h1:humidity:HM-20:pct");
        add_node_from_spec("v1:vent:VT-9");
    }

    char line[LINE_MAX_LEN];
    while (fgets(line, sizeof(line), stdin)) {
        double id_d = 0;
        json_num(line, "id", &id_d);
        long rid = (long)id_d;

        char tool[64] = {0};
        if (!json_str(line, "tool", tool, sizeof(tool))) {
            printf("{\"id\":%ld,\"ok\":false,\"error\":\"missing tool\"}\n", rid);
            continue;
        }

        /* Who is on the bus. This is the reply everything upstream is built on. */
        if (strcmp(tool, "bus.list") == 0) {
            tick_environment();
            printf("{\"id\":%ld,\"ok\":true,\"result\":{\"nodes\":[", rid);
            for (int i = 0; i < g_node_count; i++) {
                Node *n = &g_nodes[i];
                printf("%s{\"id\":\"%s\",\"role\":\"%s\",\"kind\":\"%s\","
                       "\"model\":\"%s\",\"unit\":\"%s\",\"value\":%.1f}",
                       i ? "," : "", n->id, n->role, n->kind, n->model,
                       n->unit, n->value);
            }
            printf("]}}\n");

        } else if (strcmp(tool, "node.read") == 0) {
            char nid[24] = {0};
            json_str(line, "node", nid, sizeof(nid));
            tick_environment();
            Node *n = find_node(nid);
            if (!n) {
                printf("{\"id\":%ld,\"ok\":false,\"error\":\"no such node\"}\n", rid);
            } else {
                printf("{\"id\":%ld,\"ok\":true,\"result\":{\"node\":\"%s\","
                       "\"kind\":\"%s\",\"unit\":\"%s\",\"value\":%.1f}}\n",
                       rid, n->id, n->kind, n->unit, n->value);
            }

        } else if (strcmp(tool, "node.set") == 0) {
            char nid[24] = {0};
            double v = 0;
            json_str(line, "node", nid, sizeof(nid));
            json_num(line, "value", &v);
            Node *n = find_node(nid);
            if (!n || strcmp(n->role, "actuator") != 0) {
                printf("{\"id\":%ld,\"ok\":false,"
                       "\"error\":\"not an actuator\"}\n", rid);
            } else {
                /* The relay clamps its own range. Whatever the rule upstream
                 * decided, the hardware still refuses to exceed itself. */
                if (v < 0) v = 0;
                if (v > 100) v = 100;
                n->value = v;
                tick_environment();
                printf("{\"id\":%ld,\"ok\":true,\"result\":{\"node\":\"%s\","
                       "\"value\":%.1f}}\n", rid, n->id, n->value);
            }

        } else {
            printf("{\"id\":%ld,\"ok\":false,\"error\":\"unknown tool\"}\n", rid);
        }
    }
    return 0;
}
