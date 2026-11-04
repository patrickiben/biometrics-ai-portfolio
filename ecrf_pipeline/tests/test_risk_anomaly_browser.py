"""Independent intake and known-answer checks for browser risk/monitoring workspaces.

Run directly with the app dependencies installed. The production tier functions are
loaded before their Streamlit UI; no analysis implementation is copied into tests.
"""
import io
import copy
import csv
import hashlib
import json
import pathlib
import sys
import unittest
import zipfile

import pandas as pd

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "eval"))
from _app import load_app


def longitudinal_rows():
    return [
        {"USUBJID": f"{lab}{i}", "DAY": day, "LAB": lab,
         "ALT": 10 * i + (20 if lab == "B" and day == 1 else 0)}
        for lab in ("A", "B") for i in range(1, 4) for day in (0, 1)
    ]


class MonitoringKnownAnswers(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = load_app("anomaly")
        # The browser ships this explicitly labeled approximation. Native optional
        # Sinkhorn coverage remains in qc_test.py, rather than changing this oracle.
        cls.app["REAL_OT"] = False
        cls.meta = {"numcols": ["ALT"], "timecol": "DAY", "labcol": "LAB"}

    def test_between_lab_counts_distinct_current_participants(self):
        view = pd.DataFrame(longitudinal_rows()).set_index("USUBJID")
        result = self.app["tier3_lab_compare"](view, self.meta, self.app["DEFAULT_THR"])
        self.assertEqual(set(result.lab), {"A", "B"})
        self.assertEqual(result.n.tolist(), [3, 3])
        self.assertEqual(result.n_others.tolist(), [3, 3])
        self.assertEqual(result.transport_distance.tolist(), [20.0, 20.0])

    def test_undersized_third_lab_does_not_enter_other_lab_pool(self):
        rows = [r for r in longitudinal_rows() if r["DAY"] == 1]
        rows.append({"USUBJID": "C1", "DAY": 1, "LAB": "C", "ALT": 9999})
        view = pd.DataFrame(rows).set_index("USUBJID")
        result = self.app["tier3_lab_compare"](view, self.meta, self.app["DEFAULT_THR"])
        self.assertEqual(set(result.lab), {"A", "B"})
        self.assertEqual(result.n.tolist(), [3, 3])
        self.assertEqual(result.n_others.tolist(), [3, 3])
        self.assertEqual(result.transport_distance.tolist(), [20.0, 20.0])

    def test_visit_count_does_not_reweight_between_lab_distributions(self):
        rows = longitudinal_rows()
        # Extra historical visits for a single participant must not give that
        # participant extra mass in a comparison of current participant values.
        rows.extend({"USUBJID": "A1", "DAY": day, "LAB": "A", "ALT": 10}
                    for day in (-3, -2, -1))
        view = pd.DataFrame(rows).set_index("USUBJID")
        result = self.app["tier3_lab_compare"](view, self.meta, self.app["DEFAULT_THR"])
        self.assertEqual(result.n.tolist(), [3, 3])
        self.assertEqual(result.n_others.tolist(), [3, 3])
        self.assertEqual(result.transport_distance.tolist(), [20.0, 20.0])


class BrowserContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.risk, cls.anomaly = load_app("risk"), load_app("anomaly")

    def risk_input(self):
        data = b"protocol,person,interval,units\nSTUDY-QC,001,490,ms\nSTUDY-QC,001,500,ms\nSTUDY-QC,002,501,ms\n"
        config = {"files": {"ecg.csv": {"domain": "eg", "study": "protocol",
                  "columns": {"USUBJID": "person", "EGQTC": "interval"}, "values": {},
                  "units_confirmed": True, "unit_checks": {"units": "ms"}}},
                  "thresholds": dict(self.risk["DEFAULT_THR"]), "lab_limits": {}, "confirmed": True}
        return {"ecg.csv": data}, config

    def anomaly_input(self):
        rows = [{"protocol": "STUDY-QC", "person": r["USUBJID"], "visit": r["DAY"],
                 "site": r["LAB"], "measurement": r["ALT"], "units": "U/L"}
                for r in longitudinal_rows()]
        data = pd.DataFrame(rows).to_csv(index=False).encode()
        config = {"columns": {"participant": "person", "time": "visit", "lab": "site", "study": "protocol",
                  "unit": "units", "numeric": ["measurement"], "text": []}, "units": {"measurement": "U/L"},
                  "time_type": "numeric", "reference": "0", "current": "1",
                  "thresholds": dict(self.anomaly["DEFAULT_THR"]), "confirmed": True}
        return {"measurements.csv": data}, config

    def test_strict_csv_intake_and_identifier_preservation(self):
        invalid = [b"", b"id,id\n1,2\n", b"id,ID\n1,2\n", b"id,x\n1\n", b"id,x\n1,2,3\n",
                   b'id,x\n1,"unfinished\n', b"id,x\n1,\xff\n", b"id,x\n1,\x00\n", b"id,x\n"]
        for name, app in (("risk", self.risk), ("anomaly", self.anomaly)):
            for data in invalid:
                with self.subTest(app=name, data=repr(data)):
                    with self.assertRaises(ValueError): app["browser_read_csv"]("input.csv", data)
            with self.assertRaises(ValueError): app["browser_read_csv"]("../input.csv", b"id\n1\n")
            with self.assertRaises(ValueError): app["browser_read_csv"]("input.csv", b"x" * (2 * 1024 * 1024 + 1))
            parsed = app["browser_read_csv"]("input.csv", b"id,text\n001,NA\n002,NULL\n")
            self.assertEqual(parsed.to_dict("list"), {"id": ["001", "002"], "text": ["NA", "NULL"]})

    def test_qtc_boundary_maximum_and_configurable_criterion(self):
        sources, config = self.risk_input()
        result = self.risk["browser_compute"](sources, config)
        signals = result["tables"]["signals"].set_index("USUBJID")
        self.assertEqual(signals.n_qtc.to_dict(), {"001": 0, "002": 1})
        scores = result["tables"]["score_components"].set_index("USUBJID")
        self.assertEqual(scores.ecg_comp.to_dict(), {"001": 0, "002": 6})
        self.assertEqual(scores.discontinuation_risk_score.to_dict(), {"001": 0.0, "002": 0.15})
        config["thresholds"]["QTC_ABS_MS"] = 499
        changed = self.risk["browser_compute"](sources, config)
        self.assertEqual(changed["tables"]["signals"].set_index("USUBJID").n_qtc.to_dict(), {"001": 1, "002": 1})
        self.assertEqual(json.loads(changed["audit"].iloc[0]["thresholds"])["QTC_ABS_MS"], 499)

    def test_risk_rejects_mixed_study_missing_nonfinite_and_mixed_units(self):
        sources, config = self.risk_input()
        original = sources["ecg.csv"]
        for replacement in [original.replace(b"STUDY-QC,002", b"OTHER,002"),
                            original.replace(b",501,", b",,"), original.replace(b",501,", b",NaN,"),
                            original.replace(b",501,", b",Inf,"), original.replace(b",501,ms", b",501,s"),
                            original.replace(b",002,", b",,IGNotUsed,", 1)]:
            with self.subTest(replacement=replacement):
                with self.assertRaises(ValueError): self.risk["browser_compute"]({"ecg.csv": replacement}, config)
        config["files"]["ecg.csv"]["units_confirmed"] = False
        with self.assertRaises(ValueError): self.risk["browser_compute"](sources, config)

    def test_risk_source_files_with_same_stem_are_both_retained(self):
        config = {"files": {}, "thresholds": dict(self.risk["DEFAULT_THR"]), "confirmed": True}
        sources = {}
        for filename, severity in (("ae.first.csv", "MILD"), ("ae.second.csv", "SEVERE")):
            sources[filename] = ("person,intensity\n001," + severity + "\n").encode()
            config["files"][filename] = {"domain": "ae", "columns": {"USUBJID": "person", "AESEV": "intensity"},
                                        "values": {"AESEV": {severity: severity}}}
        result = self.risk["browser_compute"](sources, config)
        self.assertEqual(result["tables"]["signals"].iloc[0].n_ae, 2)
        self.assertEqual(result["tables"]["score_components"].iloc[0].ae_comp, 18)
        self.assertEqual(set(result["normalized"]), set(sources))

    def test_anomaly_matched_shift_known_answer_and_order_invariance(self):
        sources, config = self.anomaly_input()
        result = self.anomaly["browser_compute"](sources, config)
        drift = result["tables"]["drift"].iloc[0]
        self.assertEqual((drift.n_ref, drift.n_cur, drift.transport_distance), (6, 6, 10.0))
        lab = result["tables"]["lab_drift"].set_index("lab")
        self.assertEqual(lab.transport_distance.to_dict(), {"A": 0.0, "B": 20.0})
        comparison = result["tables"]["lab_compare"]
        self.assertEqual(comparison.n.tolist(), [3, 3])
        self.assertEqual(comparison.n_others.tolist(), [3, 3])
        self.assertIn("not exact OT", result["audit"].iloc[0].drift_method)
        lines = sources["measurements.csv"].splitlines()
        shuffled = {"measurements.csv": b"\n".join([lines[0]] + list(reversed(lines[1:]))) + b"\n"}
        again = self.anomaly["browser_compute"](shuffled, config)
        for table in result["tables"]:
            pd.testing.assert_frame_equal(result["tables"][table], again["tables"][table])

    def test_overlapping_risk_extracts_require_distinct_event_identity(self):
        base = {"domain": "ae", "columns": {"USUBJID": "person", "AESEV": "severity"},
                "values": {"AESEV": {"MILD": "MILD"}}}
        for first_key, second_key in ((True, True), (False, False), (True, False), (False, True)):
            config = {"files": {}, "thresholds": dict(self.risk["DEFAULT_THR"]), "confirmed": True}
            sources = {"first.csv": b"person,event,severity\n001,1,MILD\n",
                       "second.csv": b"person,event,severity\n001,1,MILD\n"}
            for name, keyed in zip(sources, (first_key, second_key)):
                config["files"][name] = dict(copy.deepcopy(base), record_id="event" if keyed else "")
            with self.subTest(first_key=first_key, second_key=second_key):
                with self.assertRaises(ValueError): self.risk["browser_compute"](sources, config)
        config["files"] = {name: dict(copy.deepcopy(base), record_id="event") for name in sources}
        sources["second.csv"] = b"person,event,severity\n001,2,MILD\n"
        result = self.risk["browser_compute"](sources, config)
        self.assertEqual(result["tables"]["signals"].iloc[0].n_ae, 2)
        self.assertEqual(result["tables"]["score_components"].iloc[0].ae_comp, 4)

    def test_derived_csv_headers_are_formula_safe_and_html_is_inert(self):
        sources, config = self.anomaly_input()
        column = '=HYPERLINK("https://example.invalid")'
        frame = pd.read_csv(io.BytesIO(sources["measurements.csv"]), dtype=str)
        frame = frame.rename(columns={"measurement": column})
        hostile = '<img src=x onerror="globalThis.ecrfXSS=1">'
        frame["person"] = frame.person.replace({"A1": hostile})
        sources["measurements.csv"] = frame.to_csv(index=False).encode()
        config["columns"]["numeric"] = [column]; config["units"] = {column: "U/L"}
        result = self.anomaly["browser_compute"](sources, config)
        with zipfile.ZipFile(io.BytesIO(self.anomaly["browser_package"](result, sources))) as archive:
            headers = next(csv.reader(io.StringIO(archive.read("normalized/measurements.csv").decode())))
            self.assertIn("'" + column, headers)
            records = json.loads(archive.read("normalized/measurements.csv.json"))
            self.assertIn(column, records["data"][0])
            report = archive.read("report.html").decode()
            self.assertNotIn(hostile, report)
            self.assertNotIn('<img src=x', report)

    def test_anomaly_rejects_unmatched_ambiguous_or_incompatible_measurements(self):
        sources, config = self.anomaly_input()
        frame = pd.read_csv(io.BytesIO(sources["measurements.csv"]), dtype=str)
        mutations = [frame.iloc[:-1], pd.concat([frame, frame.iloc[:1]])]
        for column, value in [("protocol", "OTHER"), ("units", "mg/dL"), ("site", "CHANGED"),
                              ("measurement", ""), ("measurement", "Inf"), ("person", "")]:
            changed = frame.copy(); changed.loc[0, column] = value; mutations.append(changed)
        for changed in mutations:
            with self.subTest(rows=len(changed), first=changed.iloc[0].to_dict()):
                with self.assertRaises(ValueError):
                    self.anomaly["browser_compute"]({"measurements.csv": changed.to_csv(index=False).encode()}, config)

    def test_anomaly_iso_date_pair_matches_numeric_pair(self):
        sources, config = self.anomaly_input()
        expected = self.anomaly["browser_compute"](sources, config)
        frame = pd.read_csv(io.BytesIO(sources["measurements.csv"]), dtype=str)
        frame["visit"] = frame.visit.map({"0": "2026-01-01", "1": "2026-01-08"})
        config.update(time_type="ISO date", reference="2026-01-01", current="2026-01-08")
        actual = self.anomaly["browser_compute"]({"measurements.csv": frame.to_csv(index=False).encode()}, config)
        pd.testing.assert_frame_equal(expected["tables"]["drift"], actual["tables"]["drift"])
        config["current"] = "2026-02-30"
        with self.assertRaises(ValueError): self.anomaly["browser_compute"](sources, config)

    def test_unreviewed_and_invalid_thresholds_cannot_execute(self):
        for app, factory in ((self.risk, self.risk_input), (self.anomaly, self.anomaly_input)):
            sources, config = factory(); config["confirmed"] = False
            with self.assertRaises(ValueError): app["browser_compute"](sources, config)
            config["confirmed"] = True
            for value in (True, 0, -1, float("inf"), float("nan")):
                invalid = copy.deepcopy(config); invalid["thresholds"][next(iter(invalid["thresholds"]))] = value
                with self.assertRaises(ValueError): app["browser_compute"](sources, invalid)

    def test_complete_exports_escape_derived_text_and_reject_stale_inputs(self):
        for app, factory in ((self.risk, self.risk_input), (self.anomaly, self.anomaly_input)):
            sources, config = factory()
            filename = next(iter(sources))
            original_id = b"001" if app is self.risk else b"A1"
            sources[filename] = sources[filename].replace(original_id, b"=1+1")
            result = app["browser_compute"](sources, config)
            with zipfile.ZipFile(io.BytesIO(app["browser_package"](result, sources))) as archive:
                self.assertIsNone(archive.testzip())
                self.assertEqual(archive.read("inputs/" + filename), sources[filename])
                normalized = list(csv.DictReader(io.StringIO(archive.read("normalized/" + filename).decode())))
                self.assertTrue(any(row["USUBJID"] == "'=1+1" for row in normalized))
                self.assertIn(b'"=1+1"', archive.read("normalized/" + filename + ".json"))
                inventory = json.loads(archive.read("file_inventory.json"))
                for name, digest in inventory.items():
                    self.assertEqual(hashlib.sha256(archive.read(name)).hexdigest(), digest)
            changed = {**sources, filename: sources[filename] + b"\n"}
            with self.assertRaises(ValueError): app["browser_package"](result, changed)


if __name__ == "__main__":
    unittest.main(verbosity=2)
