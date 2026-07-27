import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {readFile} from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const configuration = JSON.parse(
  await readFile(new URL("config/messkonfiguration.v2.json", root), "utf8"),
);
const manifest = JSON.parse(
  await readFile(new URL("config/testaufnahme-manifest.v2.json", root), "utf8"),
);
const documentation = await readFile(
  new URL("docs/messaufbau-und-datengrundlage.md", root),
  "utf8",
);
const dashboard = await readFile(new URL("intakt_dashboard.html", root), "utf8");
const test01Quality = JSON.parse(
  await readFile(new URL("outputs/test01_import_qa/quality_report.json", root), "utf8"),
);

test("five canonically labelled sensors including the saddle girth are configured", () => {
  assert.deepEqual(
    configuration.sensors.map((sensor) => sensor.label).sort(),
    ["HL", "HR", "SG", "VL", "VR"],
  );
  assert.equal(
    new Set(configuration.sensors.filter((sensor) => sensor.hardware_id).map((sensor) => sensor.hardware_id)).size,
    5,
  );
  for (const sensor of configuration.sensors) {
    assert.match(sensor.hardware_id, /^[0-9A-F]{12}$/);
    assert.ok(sensor.position);
  }
});

test("coordinate system, sampling decision, units and uncertainty are explicit", () => {
  assert.equal(configuration.coordinate_system.handedness, "right");
  for (const axis of ["positive_x", "positive_y", "positive_z"]) {
    assert.ok(configuration.coordinate_system[axis]);
  }
  assert.equal(configuration.sampling.sensor_bandwidth_hz, 44);
  assert.equal(configuration.sampling.bandwidth_source, "user_confirmed_operational_setting");
  assert.ok(configuration.sampling.uncertainty);
  assert.deepEqual(
    configuration.channels.map((channel) => channel.raw_unit),
    ["g", "degree_per_second", "degree"],
  );
  assert.ok(configuration.channels.every((channel) => channel.unit_status));
});

test("raw-data integrity policy and honest evidence status are enforced", () => {
  assert.equal(configuration.raw_data_policy.immutable, true);
  assert.equal(configuration.raw_data_policy.integrity_algorithm, "sha256");
  assert.equal(configuration.evidence.complete_test_recording_present, true);
  assert.equal(configuration.evidence.matching_video_present, true);
  assert.equal(configuration.evidence.axis_verification_present, true);
  assert.equal(configuration.evidence.mirror_transform_empirically_verified, false);
  assert.equal(manifest.complete, false);
  assert.equal(manifest.video_file, null);
});

test("recording manifest covers every configured sensor without fabricated observations", () => {
  const configured = configuration.sensors.map((sensor) => sensor.label).sort();
  const templated = manifest.sensors.map((sensor) => sensor.label).sort();
  assert.deepEqual(templated, configured);
  assert.equal(manifest.recording_id, null);
  assert.deepEqual(manifest.observed_export.columns, []);
  assert.ok(manifest.sensors.every((sensor) => sensor.raw_files.length === 0));
});

test("documentation and dashboard expose Goal 1 artefacts and pending blockers", () => {
  for (const phrase of [
    "INTAKT-IMU-5S-V2",
    "ABGENOMMEN MIT EINSCHRÄNKUNGEN",
    "fünf Sensoren",
    "passendes Video",
  ]) {
    assert.ok(documentation.includes(phrase), `missing documentation phrase: ${phrase}`);
  }
  assert.ok(dashboard.includes('id="measurement-setup"'));
  assert.ok(dashboard.includes("Fünf Sensoren"));
  assert.ok(dashboard.includes("Abgenommen mit Einschränkungen"));
  assert.ok(dashboard.includes("44 Hz"));
  assert.ok(dashboard.includes("C5C720831275"));
});

test("dashboard inline JavaScript remains syntactically valid", () => {
  const scripts = [...dashboard.matchAll(/<script>([\s\S]*?)<\/script>/g)];
  assert.equal(scripts.length, 1);
  assert.doesNotThrow(() => new Function(scripts[0][1]));
});

test("dashboard contains the index-based time reconstruction subgoal", () => {
  const synchronizationGoal = dashboard.indexOf(
    'title:"Sensoren zeitlich synchronisieren"',
  );
  const indexingSubgoal = dashboard.indexOf(
    'title:"Samplezeiten durch Indexierung rekonstruieren"',
  );
  const preprocessingGoal = dashboard.indexOf(
    'title:"Signale vorverarbeiten"',
  );

  assert.ok(synchronizationGoal >= 0);
  assert.ok(indexingSubgoal > synchronizationGoal);
  assert.ok(preprocessingGoal > indexingSubgoal);
  assert.ok(
    dashboard.includes('parentGoal:"Sensoren zeitlich synchronisieren"'),
  );
  assert.ok(dashboard.includes("Indexbasierte Analysezeit je Sensor rekonstruieren"));
  assert.ok(dashboard.includes("Rekonstruktionsfehler und Unsicherheit"));
  assert.ok(dashboard.includes("migrateGoalStorageForIndexingSubgoal"));
  assert.ok(dashboard.includes('localStorage.setItem(schemaKey,"3")'));
  assert.ok(
    dashboard.match(/localStorage\.setItem\("intakt_goal_schema_version","3"\)/g)
      ?.length >= 2,
  );
});

test("dashboard provides a local five-sensor test-recording repository", () => {
  for (const id of [
    "recording-storage",
    "recordingForm",
    "recordingId",
    "fileSensorData",
    "fileVideo",
    "filePhotos",
    "recordingList",
  ]) {
    assert.ok(dashboard.includes(`id="${id}"`), `missing recording storage element: ${id}`);
  }
  assert.ok(dashboard.includes('const recordingDbName="intakt-testversuche"'));
  assert.ok(dashboard.includes("indexedDB.open"));
  assert.ok(dashboard.includes("URL.createObjectURL"));
  assert.ok(dashboard.includes('accept=".txt,text/plain"'));
  assert.ok(dashboard.includes('"SENSORDATEN"'));
  assert.ok(dashboard.includes("window.showDirectoryPicker"));
  assert.ok(dashboard.includes("createWritable"));
  assert.ok(dashboard.includes('getDirectoryHandle("raw"'));
  assert.ok(dashboard.includes('getFileHandle("manifest.json"'));
  assert.ok(dashboard.includes("Der Ordner und seine Originaldateien bleiben erhalten."));
});

test("Test 1 quality evidence matches all five sensors and the immutable raw file", async () => {
  assert.equal(test01Quality.quality_observations.all_five_sensors_present, true);
  assert.equal(test01Quality.quality_observations.saddle_girth_mounting_photo_present, true);
  assert.equal(test01Quality.quality_observations.saddle_girth_hardware_id_confirmed_by_axis_screenshot, true);
  assert.deepEqual(test01Quality.quality_observations.direct_axis_evidence_labels, ["SG", "HL"]);
  assert.equal(test01Quality.quality_observations.direct_axis_evidence_count, 2);
  assert.equal(test01Quality.quality_observations.axis_orientation_documented_all_sensors, true);
  assert.equal(test01Quality.quality_observations.left_right_mounting, "mirrored");
  assert.equal(test01Quality.quality_observations.raw_axis_transform_applied, false);
  assert.equal(test01Quality.quality_observations.mirror_transform_empirically_verified, false);
  assert.equal(test01Quality.sensors.length, 5);
  assert.deepEqual(
    test01Quality.sensors.map((sensor) => sensor.label).sort(),
    ["HL", "HR", "SG", "VL", "VR"],
  );
  assert.ok(test01Quality.sensors.every((sensor) => sensor.row_rate_hz > 99));
  assert.ok(test01Quality.sensors.every((sensor) => sensor.reception_gaps_over_100_ms > 0));
  const raw = await readFile(new URL(test01Quality.source.raw_file, root));
  const sha256 = createHash("sha256").update(raw).digest("hex");
  assert.equal(sha256, test01Quality.source.raw_file_sha256);
  assert.equal(raw.byteLength, test01Quality.source.raw_file_bytes);
});
