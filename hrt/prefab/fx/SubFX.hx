package hrt.prefab.fx;

@:prefabIcon(HuiRes.ui.icons.prefab.sub_fx)
@:prefabName("Sub FX")
class SubFX extends Reference implements hrt.prefab.fx.Event.IEvent{

	@:s public var time(default, set) : Float;
	@:s public var loop(default, set) : Bool;
	@:s public var speed(default, set) : Float = 1.0;
	@:s public var duration : Float;
	/** Values of parameters of the referenced FX, by name. A curve `paramCurveName(name)` animates one instead, in the time of the parent FX **/
	@:s public var params : Dynamic;

	var instance : hrt.prefab.fx.FX.FXAnimation;

	public static inline function paramCurveName(name: String) {
		// not a channel of the object (position, color...), which are read by prefix before the ':'
		return "param:" + name;
	}

	public var hidden:Bool = false;
	public var lock:Bool = false;
	public var selected:Bool = false;


	override function postMakeInstance() : Void {
		if (refInstance != null) {
			var fxanim : hrt.prefab.fx.FX.FXAnimation = refInstance.findFirstLocal3d().find(o -> Std.downcast(o, hrt.prefab.fx.FX.FXAnimation));
			if(fxanim != null) {
				fxanim.startDelay = time;
				fxanim.loop = loop;
				fxanim.playSpeed = speed;
				instance = fxanim;
				applyParams();
			}
		}
	}

	// after the init of the sub FX, which sets its parameters to their defaults
	function applyParams() {
		if (params == null)
			return;
		for (name in Reflect.fields(params))
			instance.setParameter(name, Reflect.field(params, name));
	}

	function set_time(v) {
		#if editor
		if(instance != null)
			instance.startDelay = v;
		#end
		return time = v;
	}

	function set_speed(v) {
		#if editor
		if(instance != null)
			instance.playSpeed = v;
		#end
		return speed = v;
	}

	public function getDuration() {
		if (instance != null)
			return instance.duration / speed;
		return 0.0;
	}

	#if editor
	// stretching the strip changes the playback speed
	public function setDuration(v : Float) : Void {
		if (instance != null && instance.duration > 0 && v > 0)
			speed = instance.duration / v;
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

	override function updateInstance(?propName:String) {
		super.updateInstance(propName);

		if (propName == "loop") {
			postMakeInstance();
		}

		#if editor
		// an override removed (undo) goes back to the default
		if (instance != null) {
			instance.setParameters(Std.downcast(refInstance, FX)?.parameters);
			applyParams();
		}
		#end
	}

	override function edit2( ctx : hrt.prefab.EditContext2 ) {
		ctx.build(
			<category("Event")>
				<slider field={time} defaultValue={0.0}/>
				<checkbox field={loop}/>
				<slider field={speed} min={0.01} defaultValue={1.0}/>
			</category>
		);

		var fx = Std.downcast(refInstance, FX);
		if (fx != null && fx.parameters.length > 0) {
			ctx.build(
				<category("FX Parameters") id="paramsCat"/>
			);
			for (p in fx.parameters) {
				var widget = paramsCat.buildProp({ name: p.name, t: hrt.prefab.Props.PropType.PFloat(0, 1), def: p.def }, params ?? {});
				if (widget.value == null)
					widget.value = p.def;
				widget.anim = paramCurveName(p.name);
				// only the parameters set here are saved
				@:privateAccess widget.onFieldChange = (_) -> {
					params ??= {};
					Reflect.setField(params, p.name, widget.value);
				};
			}
		}

		super.edit2(ctx);
	}

	#if editor

	public function getDisplayInfo(ctx:hide.prefab.EditContext) {
		var ref = Std.downcast(resolve(), FX);
		return {
			label: ref != null ? new haxe.io.Path(source).file + (speed != 1 ? ' x${hxd.Math.fmt(speed)}' : "") : "null",
			length: ref != null ? ref.duration / speed : 1.0,
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