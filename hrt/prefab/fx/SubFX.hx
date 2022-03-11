package hrt.prefab.fx;

class SubFX extends Reference implements hrt.prefab.fx.Event.IEvent{

	@:s public var time(default, set) : Float;

	#if editor
	var instance : hrt.prefab.fx.FX.FXAnimation;
	#end

	public function new(?parent) {
		super(parent);
		this.type = "subFX";
	}

	override function makeInstance(ctx:Context):Context {
		var ctx = super.makeInstance(ctx);
		var fxanim = ctx.local3d.find(o -> Std.downcast(o, hrt.prefab.fx.FX.FXAnimation));
		if(fxanim != null) {
			fxanim.startDelay = time;
			#if editor
			instance = fxanim;
			#end
		}
		return ctx;
	}

	function set_time(v) {
		#if editor
		if(instance != null)
			instance.startDelay = v;
		#end
		return time = v;
	}

	#if editor

	override function edit( ctx : EditContext ) {
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

	public function getDisplayInfo(ctx:EditContext) {
		var ref = Std.downcast(resolveRef(ctx.rootContext.shared), FX);
		return {
			label: ref != null ? new haxe.io.Path(source).file : "null",
			length: ref != null ? ref.duration : 1.0
		};
	}

	override function getHideProps() : HideProps {
		return {
			icon : "play-circle", name : "SubFX",
			allowChildren: function(s) return false
		};
	}
	#end

	static var _ = Library.register("subFX", SubFX);

}