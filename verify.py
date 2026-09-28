#!/usr/bin/env python3
"""greenhouse-independent: the same server and the same rules run against two installations; the sensor changes model and unit, the control code does not."""
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "tools"))
from appplayer import AppPlayer  # noqa: E402
from mcpclient import Server  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
CAP = os.path.join(HERE, "captures")

SERVER = os.path.join(HERE, "greenhouse_server")
A = ["t1:temperature:TH-100:C", "h1:humidity:HM-20:pct", "v1:vent:VT-9"]
B = ["t1:temperature:FX-200:F", "h1:humidity:HM-20:pct", "c1:co2:CO-5:ppm", "v1:vent:VT-9"]

for label, install in (("A", A), ("B", B)):
    with Server(["dart", "run", "bin/server.dart", *install], cwd=SERVER) as s:
        st = s.call("bus.state")
        assert st["sensorCount"] == len(install) - 1 and st["actuatorCount"] == 1, st
        applied = s.call("rules.apply")
        assert applied["ruleLog"], f"{label}: the rules produced no decision"
src = open(os.path.join(SERVER, "lib", "rules.dart")).read()
assert "TH-100" not in src and "FX-200" not in src, "the rules must not name a sensor model"

ap = AppPlayer()
for label, install in (("A", A), ("B", B)):
    ap.register_server(f"com.makemind.sample.greenhouse.{label.lower()}", f"Greenhouse {label}", cwd=SERVER,
                       args=["run", "bin/server.dart", f"--house={label}", *install])
for label, model in (("A", "TH-100"), ("B", "FX-200")):
    ap.restart()
    ap.open_server(f"com.makemind.sample.greenhouse.{label.lower()}")
    ap.wait_text(model)
    ap.expect_text(f"HOUSE {label}")
    ap.shot(f"{CAP}/{label}_1_discovered.png")
    ap.tap("Apply the rules")
    ap.wait_text("-> v1=")          # the rule log, not the vent row that was already there
    time.sleep(1)
    ap.shot(f"{CAP}/{label}_2_rules_applied.png")
print("greenhouse-independent: two installations, one server, same rules applied on both screens")
