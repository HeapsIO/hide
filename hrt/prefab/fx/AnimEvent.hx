package hrt.prefab.fx;

class AnimEvent extends hrt.prefab.fx.Event {

	@:s public var animation: String;
	@:s public var loop: Bool = false;
	@:s public var speed : Float = 1.0;
	@:s public var offset : Float = 0.0;

	var animTemplate : h3d.anim.Animation;

	override function new(parent, shared) {
		super(parent, shared);
	}

	override function makeInstance() {
		animTemplate = animation != null ? shared.loadAnimation(animation) : null;
	}

	override function prepare() : Event.EventInstance {
		var obj = findFirstLocal3d();
		var lastTime = -1.0;
		var inst = null;
		if(animTemplate == null) { return null; }
		return {
			evt: this,
			setTime: function(localTime) {
				var duration = getDuration();
				if(localTime > 0 && (localTime < duration || loop)) {
					if(inst == null) {
						inst = obj.playAnimation(animTemplate);
						inst.pause = true;
						inst.loop = loop;
					}
					var t = hxd.Math.max(0,(localTime + offset) * animTemplate.sampling * animTemplate.speed * speed);
					if (loop) {
						t = t % animTemplate.frameCount;
					}
					else {
						t = hxd.Math.min(t, animTemplate.frameCount);
					}
					inst.setFrame(t);
				}
				else inst = null;
				lastTime = localTime;
			}
		}
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		super.edit(ctx);
		var props = ctx.properties.add(new hide.Element('
			<div class="group" name="Event">
				<dl>
					<dt>Time</dt><dd><input type="number" value="0" field="time"/></dd>
					<dt>Loop</dt><dd><input type="checkbox" field="loop"/></dd>
					<dt>Animation</dt><dd><input id="anim" value="--- Choose ---"></dd>
					<dt>Speed</dt><dd><input type="number" value="0" field="speed"/></dd>
					<dt>Duration</dt><dd><input type="number" value="0" field="duration"/></dd>
					<dt>Offset</dt><dd><input type="number" value="0" field="offset"/></dd>
				</dl>
			</div>
		'),this, function(pname) {
			ctx.onChange(this, pname);
		});

		if(parent.source != null) {

			var anims = try ctx.scene.listAnims(parent.source) catch(e: Dynamic) [];
			var elts: Array<hide.comp.Dropdown.Choice> = [];
			for( a in anims )
				elts.push({id : ctx.ide.makeRelative(a), ico : null, text : ctx.scene.animationName(a), classes : ["compact"]});

			var select = new hide.comp.Select(null, props.find("#anim"), elts, false);
			select.value = animation;
			select.onChange = function(newAnim : String) {
				var prev = animation;
				if( newAnim == "" ) {
					animation = null;
				} else {
					animation = newAnim;
				}
				ctx.rebuildPrefab(this);
				ctx.properties.undo.change(Field(this, "animation", prev), () -> ctx.rebuildPrefab(this));
				ctx.onChange(this, "animation");
			}
		}
	}

	override function getHideProps() : hide.prefab.HideProps {
		return {
			icon : "play-circle", name : "AnimEvent",
			allowParent : (p) -> Std.downcast(p,hrt.prefab.Model) != null,
			allowChildren: function(s) return false
		};
	}

	override function getDisplayInfo(ctx: hide.prefab.EditContext) {
		var anim = null;
		if(animation != null) {
			try {
				anim = shared.loadAnimation(animation);
			} catch(e : hxd.res.NotFound) { }
		}
		return {
			label: anim != null ? ctx.scene.animationName(animation) : "null",
			loop: loop,
		}
	}
	#end

	public override function getDuration() : Float {
		return duration > 0.0 ? duration : (animTemplate != null ? animTemplate.getDuration() : 0.0);
	}

	static var _ = Prefab.register("animEvent", AnimEvent);

}