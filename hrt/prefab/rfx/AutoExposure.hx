package hrt.prefab.rfx;

class AutoExposure extends RendererFX {

	var lightFront : Float = 0.;
	var lightBack : Float = 0.;
	var lightPower : Float = 1.;

	var transitionSpeed : Float = 1.;

	override function save() {
		var o : Dynamic = super.save();
		o.lightFront = lightFront;
		o.lightBack = lightBack;
		o.lightPower = lightPower;
		o.transitionSpeed = transitionSpeed;
		return o;
	}

	override function load(o:Dynamic) {
		super.load(o);
		lightFront = o.lightFront;
		lightBack = o.lightBack;
		lightPower = o.lightPower;
		transitionSpeed = o.transitionSpeed;
	}

	override function begin( r:h3d.scene.Renderer, step:h3d.impl.RendererFX.Step ) {
		if( step != BeforeTonemapping )
			return;
		var exp = 0.;
		var l = @:privateAccess r.ctx.lights;
		var mainLight = null;
		while( l != null ) {
			var pbrLight = Std.downcast(l, h3d.scene.pbr.DirLight);
			if( pbrLight != null && pbrLight.isMainLight ) {
				mainLight = pbrLight;
				break;
			}
			l = l.next;
		}
		if( mainLight != null ) {
			var dir = mainLight.getDirection().dot(r.ctx.camera.target.sub(r.ctx.camera.pos).normalized());
			dir = (dir + 1) * 0.5;
			exp += hxd.Math.lerp(lightFront, lightBack, Math.pow(dir, lightPower * lightPower));
		}
		var render = cast(r,h3d.scene.pbr.Renderer);
		var f = 1 - Math.pow(1 - transitionSpeed * transitionSpeed, r.ctx.elapsedTime * 60);
		render.exposure = hxd.Math.lerp(render.exposure, exp, f);
	}

	#if editor
	override function edit( ctx : hide.prefab.EditContext ) {
		var pr = ctx.properties.add(new hide.Element('
			<dl>
			<dt>Light Front</dt><dd><input type="range" min="-2" max="2" field="lightFront"/></dd>
			<dt>Light Back</dt><dd><input type="range" min="-2" max="2" field="lightBack"/></dd>
			<dt>Light Power</dt><dd><input type="range" min="0" max="3" field="lightPower"/></dd>
			<dt>Transition Speed</dt><dd><input type="range" min="0" max="1" field="transitionSpeed"/></dd>
			</dl>
			<dl>
				<dt>Current</dt><dd id="value"></dd>
			</dl>
		'),this);
		ctx.addUpdate(function(_) {
			var render = cast(ctx.scene.s3d.renderer, h3d.scene.pbr.Renderer);
			pr.find("#value").text(""+hxd.Math.fmt(render.exposure));
		});
	}
	#end

	static var _ = Library.register("rfx.autoexp", AutoExposure);

}