package hrt.prefab.fx;

class SubFX extends Reference implements hrt.prefab.fx.Event.IEvent{

	@:s public var time(default, set) : Float;
	@:s public var loop(default, set) : Bool;
	@:s public var duration : Float;

	var instance : hrt.prefab.fx.FX.FXAnimation;

	public var hidden:Bool = false;
	public var lock:Bool = false;
	public var selected:Bool = false;


	override function postMakeInstance() : Void {
		if (refInstance != null) {
			var fxanim : hrt.prefab.fx.FX.FXAnimation = refInstance.findFirstLocal3d().find(o -> Std.downcast(o, hrt.prefab.fx.FX.FXAnimation));
			if(fxanim != null) {
				fxanim.startDelay = time;
			    fxanim.loop = loop;
				instance = fxanim;
			}
		}
	}

	function set_time(v) {
		#if editor
		if(instance != null)
			instance.startDelay = v;
		#end
		return time = v;
	}

	public function getDuration() {
		if (refInstance != null) {
			var local = refInstance.findFirstLocal3d();
			if (local == null)
				return 0.0;
			var fxAnim : hrt.prefab.fx.FX.FXAnimation = local.find(o -> Std.downcast(o, hrt.prefab.fx.FX.FXAnimation));
			if (fxAnim != null) {
				return fxAnim.duration;
			}
		}
		return 0.0;
	}

	#if editor
	public function setDuration(v) : Void {
		duration = v;
	}
	#end

	function set_loop(v) {
		#if editor
		if(instance != null)
			instance.loop = v;
		#end
		return loop = v;
	}

	public function getEventPrefab() { return this; }

	public function prepare() : Event.EventInstance {
		return {
			evt: this
		};
	}

	#if editor

	override function edit( ctx : hide.prefab.EditContext ) {
		var props = ctx.properties.add(new hide.Element('
			<div class="group" name="Event">
				<dl>
					<dt>Time</dt><dd><input type="number" value="0" field="time"/></dd>
					<dt>Loop</dt><dd><input type="checkbox" field="loop"/></dd>
				</dl>
			</div>
		'),this, function(pname) {
			ctx.onChange(this, pname);
		});
		super.edit(ctx);
	}

	public function getDisplayInfo(ctx:hide.prefab.EditContext) {
		var ref = Std.downcast(resolveRef(), FX);
		return {
			label: ref != null ? new haxe.io.Path(source).file : "null",
			length: ref != null ? ref.duration : 1.0,
			loop: loop
		};
	}

	override function getHideProps() : hide.prefab.HideProps {
		return {
			icon : "play-circle", name : "SubFX"
		};
	}
	#end

	static var _ = Prefab.register("subFX", SubFX);

}