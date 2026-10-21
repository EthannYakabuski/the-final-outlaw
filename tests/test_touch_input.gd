extends SceneTree
## Synthetic pointers through the real engine Viewport, not native Android QA.
class Adapter extends Node:
	var covered:=false
	func fullscreen_ad_active() -> bool:return covered
	func can_reward() -> bool:return false
	func set_menu_visible(_visible:bool) -> void:pass
	func unlock(_key:String) -> void:pass
	func submit(_key:String,_value:int) -> void:pass
var game
var adapter:Adapter
var original:Node
var checks:=0
var failures:=0
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func frames(n:int=3) -> void:
	for i in range(n):await process_frame
func touch(index:int,point:Vector2,pressed:bool,canceled:bool=false) -> void:
	var event:=InputEventScreenTouch.new();event.index=index;event.position=point;event.pressed=pressed;event.canceled=canceled
	Input.parse_input_event(event);await frames()
func drag(index:int,point:Vector2) -> void:
	var event:=InputEventScreenDrag.new();event.index=index;event.position=point;event.relative=Vector2(35,0)
	Input.parse_input_event(event);await frames()
func _initialize() -> void:run.call_deferred()
func run() -> void:
	root.size=Vector2i(540,960)
	original=root.get_node_or_null("Services")
	if is_instance_valid(original):original.name="TouchTestOriginalServices"
	adapter=Adapter.new();adapter.name="Services";root.add_child(adapter)
	game=load("res://main.tscn").instantiate();game.smoke=true;game.set_process(false);root.add_child(game);game.set_process(false);await frames()
	check(not game.is_processing(),"pointer fixture owns simulation clock after scene ready")
	game._start_level(1,false);await frames()
	await touch(0,Vector2(95,850),true)
	check(game.joystick_active and game.joystick_index==0,"first pointer owns movement by actual touch ID")
	await drag(0,Vector2(145,850));check(game._movement().x>0,"owned drag moves the stick")
	await touch(1,Vector2(430,850),true)
	check(game.fire_held and game.fire_index==1 and game.joystick_index==0,"second pointer independently holds gun")
	var before:Vector2=game.battle.player;var ammo:int=game.battle.ammo
	game.battle.step(.05,game._movement(),false,game._fire_input());game.fire_request=false
	game._update_ammo_hud() # The runtime refreshes this after every battle step.
	check(game.battle.player!=before and game.battle.ammo==ammo-1,"same actual input frame moves and fires")
	await touch(2,Vector2(430,927),true)
	check(game.reload_request and game.fire_index==1 and game.joystick_index==0,"third-pointer reload preserves both owners")
	await touch(2,Vector2(430,927),false)
	check(game.fire_held and game.joystick_active,"unrelated release cannot stop gun or movement")
	game.reload_request=false
	await touch(1,Vector2(430,850),false)
	check(not game.fire_held and game.fire_index==-1 and game.joystick_active,"gun release only releases gun")
	await touch(0,Vector2(145,850),false)
	check(not game.joystick_active and game.joystick_index==-1,"movement release only releases movement")
	await touch(0,Vector2(430,850),true)
	await touch(1,Vector2(95,850),true)
	check(game.fire_index==0 and game.joystick_index==1,"gun-first pointer ordering also works")
	await drag(0,Vector2(320,790))
	check(game.fire_held and game.joystick_index==1,"gun retains its pointer when dragged outside")
	await touch(0,Vector2(320,790),false,true)
	check(not game.fire_held and game.joystick_active,"canceled gun touch releases without stealing movement")
	await touch(1,Vector2(95,850),false)
	await touch(0,Vector2(281,864),true)
	check(game.dash_request and not game.joystick_active,"dash touch owns no joystick")
	await touch(0,Vector2(281,864),false)
	game._clear_arena_input()
	await touch(0,Vector2(430,850),true)
	game._pause();await frames()
	check(game.paused and game.fire_index==-1 and game.joystick_index==-1 and not game.fire_held,"pause clears all touch ownership")
	await touch(0,Vector2(430,850),false)
	await touch(0,Vector2(270,435),true);await touch(0,Vector2(270,435),false)
	check(not game.paused and game.screen=="play","paused GUI resume still receives ordinary touch emulation")
	await touch(0,Vector2(485,49),true);await touch(0,Vector2(485,49),false)
	check(game.paused,"native-style pause hit target works")
	var resume_count:=0
	for child in game.ui.get_children():
		if child is Button and child.text=="Keep riding":resume_count+=1
	check(resume_count==1,"pause touch creates exactly one overlay despite mouse emulation")
	await touch(0,Vector2(270,435),true);await touch(0,Vector2(270,435),false)
	adapter.covered=true
	await touch(0,Vector2(95,850),true);await touch(1,Vector2(430,850),true)
	check(game.joystick_index==-1 and game.fire_index==-1 and not game.fire_held and not game.fire_request,"SDK coverage rejects both actual touch pointers")
	await touch(1,Vector2(430,850),false);await touch(0,Vector2(95,850),false)
	adapter.covered=false;game._discard_next_combat_delta=false
	await touch(0,Vector2(430,850),true)
	check(game._fire_input(),"fresh gun touch works after fullscreen coverage")
	await touch(0,Vector2(430,850),false)
	game._pause();game._back();await frames()
	check(not game.paused and game.fire_index==-1,"Back resume has no held gun")
	await game.shutdown_audio();game.queue_free();await frames(4);game=null
	adapter.free()
	if is_instance_valid(original):original.name="Services"
	print("OUTLAW_VIEWPORT_POINTER_TESTS checks=%d failures=%d (synthetic engine events; no native Android claim)"%[checks,failures])
	quit(0 if failures==0 else 1)
