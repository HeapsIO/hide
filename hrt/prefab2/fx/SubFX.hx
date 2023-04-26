package hrt.prefab2.fx;

class SubFX extends Reference implements hrt.prefab2.fx.Event.IEvent{

	@:s public var time(default, set) : Float;
	@:s public var loop(default, set) : Bool;

	#if editor
	var instance : hrt.prefab2.fx.FX.FXAnimation;
	#end

	override function postMakeInstance() : Void {
		if (refInstance != null) {
			var fxanim : hrt.prefab2.fx.FX.FXAnimation = refInstance.findFirstLocal3d().find(o -> Std.downcast(o, hrt.prefab2.fx.FX.FXAnimation));
			if(fxanim != null) {
				fxanim.startDelay = time;
			    fxanim.loop = loop;
				#if editor
				instance = fxanim;
				#end
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

	function set_loop(v) {
		#if editor
		if(instance != null)
			instance.loop = v;
		#end
		return loop = v;
	}

	#if editor

	override function edit( ctx : hide.prefab2.EditContext ) {
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

	public function getEventPrefab() { return this; }

	public function getDisplayInfo(ctx:hide.prefab2.EditContext) {
		var ref = Std.downcast(resolveRef(), FX);
		return {
			label: ref != null ? new haxe.io.Path(source).file : "null",
			length: ref != null ? ref.duration : 1.0,
			loop: loop
		};
	}

	override function getHideProps() : hide.prefab2.HideProps {
		return {
			icon : "play-circle", name : "SubFX"
		};
	}
	#end

	static var _ = Prefab.register("subFX", SubFX);

}