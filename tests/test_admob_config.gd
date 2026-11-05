extends SceneTree
## Pure routing/export-metadata checks. No ad SDK request or live ad is made.

var checks := 0
var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: " + label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var services: Node = root.get_node("Services")
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://platform/config.json"))
	var production := {
		"banner": "ca-app-pub-7719473349082950/7328806504",
		"interstitial": "ca-app-pub-7719473349082950/1254177737",
		"rewarded": "ca-app-pub-7719473349082950/6007985971",
	}
	var samples := {
		"banner": "ca-app-pub-3940256099942544/6300978111",
		"interstitial": "ca-app-pub-3940256099942544/1033173712",
		"rewarded": "ca-app-pub-3940256099942544/5224354917",
	}
	check(config.admob.app_id == "ca-app-pub-7719473349082950~3597270042", "owner App ID retained")
	check(ProjectSettings.get_setting("admob/general/android/app_id", "") == config.admob.app_id, "manifest setting matches JSON App ID")
	check(config.admob.test_mode == false, "release configuration requests production units")
	for kind in production:
		check(config.admob[kind + "_unit_id"] == production[kind], "owner unit retained: " + kind)
		for debug_build in [false, true]:
			for force_test in [false, true]:
				var variant := config.duplicate(true)
				variant.admob.test_mode = force_test
				var actual: String = services._ad_id_for_build(variant, kind, debug_build)
				var expected: String = samples[kind] if debug_build or force_test else production[kind]
				check(actual == expected, "%s debug=%s force_test=%s routes correctly" % [kind, debug_build, force_test])
		check(services._ad_id_for_build({}, kind, false) == samples[kind], "missing config defaults to sample: " + kind)
		var missing_flag := config.duplicate(true)
		missing_flag.admob.erase("test_mode")
		check(services._ad_id_for_build(missing_flag, kind, false) == samples[kind], "missing flag defaults to sample: " + kind)
		var missing_unit := config.duplicate(true)
		missing_unit.admob.erase(kind + "_unit_id")
		check(services._ad_id_for_build(missing_unit, kind, false).is_empty(), "missing production unit does not request an ad: " + kind)
		check(services._ad_id(kind) == samples[kind], "actual debug runtime selects sample: " + kind)
	check(services._ad_id_for_build(config, "unknown", true).is_empty(), "unsupported kind cannot request an ad")
	check(services._ad_id_for_build(config, "unknown", false).is_empty(), "unsupported kind remains empty in release")
	check(services._use_test_ads(), "debug status accurately reports test ads")
	check(not services.can_reward(), "headless checks never create ad entitlement")
	print("OUTLAW_ADMOB_CONFIG_TESTS checks=%d failures=%d; no SDK requests or live ads" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
