package hrt.prefab.fx;

class AnimEvent extends hrt.prefab.fx.Event {

	public var animation: String;
	public var speed : Float = 1.0;
	public var duration : Float = 0.0;
	public var offset : Float = 0.0;

	public function new(?parent) {
		super(parent);
		this.type = "animEvent";
	}

	override function save() {
		var obj : Dynamic = super.save();
		obj.animation = animation;
		if(speed != 1.0) obj.speed = speed;
		if(duration > 0) obj.duration = duration;
		if(offset > 0) obj.offset = offset;
		return obj;
	}

	override function load(obj:Dynamic) {
		super.load(obj);
		this.animation = obj.animation;
		if(obj.speed != null) speed = obj.speed;
		if(obj.duration != null) duration = obj.duration;
		if(obj.offset != null) offset = obj.offset;
	}

	override function prepare(ctx: Context) : Event.EventInstance {
		var obj = ctx.local3d;
		var anim = animation != null ? ctx.loadAnimation(animation) : null;
		var lastTime = -1.0;
		var inst = null;
		if(anim == null) { return null; }
		return {
			evt: this,
			play: function() {
			},
			setTime: function(localTime) {
				var duration = duration > 0 ? duration : anim.getDuration();
				if(localTime > 0 && localTime < duration) {
					if(inst == null) {
						inst = obj.playAnimation(anim);
						inst.pause = true;
						inst.loop = false;
					}
					inst.setFrame(hxd.Math.clamp((localTime + offset) * anim.sampling * anim.speed * speed, 0, anim.frameCount));
				}
				else inst = null;
				lastTime = localTime;
			}
		}
	}

	#if editor
	override function edit( ctx : EditContext ) {
		super.edit(ctx);
		var props = ctx.properties.add(new hide.Element('
			<div class="group" name="Event">
				<dl>
					<dt>Time</dt><dd><input type="number" value="0" field="time"/></dd>
					<dt>Animation</dt><dd><select><option value="">-- Choose --</option></select></dd>
					<dt>Speed</dt><dd><input type="number" value="0" field="speed"/></dd>
					<dt>Duration</dt><dd><input type="number" value="0" field="duration"/></dd>
					<dt>Offset</dt><dd><input type="number" value="0" field="offset"/></dd>
				</dl>
			</div>
		'),this, function(pname) {
			ctx.onChange(this, pname);
		});

		if(parent.source != null) {
			var select = props.find("select");
			var anims = try ctx.scene.listAnims(parent.source) catch(e: Dynamic) [];
			for( a in anims )
				new hide.Element('<option>').attr("value", ctx.ide.makeRelative(a)).text(ctx.scene.animationName(a)).appendTo(select);
			if( animation != null )
				select.val(animation);
			select.change(function(_) {
				ctx.scene.setCurrent();
				var v = select.val();
				var prev = animation;
				if( v == "" ) {
					animation = null;
				} else {
					animation = v;
				}
				ctx.properties.undo.change(Field(this, "animation", prev));
				ctx.onChange(this, "animation");
			});
		}
	}

	override function getHideProps() : HideProps {
		return {
			icon : "play-circle", name : "AnimEvent",
			allowParent : (p) -> p.to(Model) != null,
			allowChildren: function(s) return false
		};
	}

	override function getDisplayInfo(ctx: EditContext) {
		var anim = null;
		if(animation != null) {
			try {
				anim = ctx.rootContext.loadAnimation(animation);
			} catch(e : hxd.res.NotFound) { }
		}
		return {
			label: anim != null ? ctx.scene.animationName(animation) : "null",
			length: duration > 0 ? duration : anim != null ? anim.getDuration() : 1.0
		}
	}
	#end

	static var _ = Library.register("animEvent", AnimEvent);

}