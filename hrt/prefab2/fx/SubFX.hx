package hrt.prefab2.fx;

class SubFX extends Reference implements hrt.prefab2.fx.Event.IEvent{

	@:s public var time(default, set) : Float;

	#if editor
	var instance : hrt.prefab.fx.FX.FXAnimation;
	#end

	public function new(?parent) {
		super(parent);
	}

	override function makeObject3d(parent3d:h3d.scene.Object):h3d.scene.Object {
		var obj = super.makeObject3d(parent3d);
		if (obj != null) {
			var fxanim = obj.find(o -> Std.downcast(o, hrt.prefab.fx.FX.FXAnimation));
			if(fxanim != null) {
				fxanim.startDelay = time;
				#if editor
				instance = fxanim;
				#end
			}
		}
		return obj;
	}

	function set_time(v) {
		#if editor
		if(instance != null)
			instance.startDelay = v;
		#end
		return time = v;
	}

	#if editor

	override function edit( ctx : hide.prefab2.EditContext ) {
		var props = ctx.properties.add(new hide.Element('
			<div class="group" name="Event">
				<dl>
					<dt>Time</dt><dd><input type="number" value="0" field="time"/></dd>
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
			length: ref != null ? ref.duration : 1.0
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