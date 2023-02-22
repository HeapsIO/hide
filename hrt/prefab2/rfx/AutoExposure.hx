package hrt.prefab2.rfx;

class AutoExposure extends RendererFX {

	@:s var lightFront : Float = 0.;
	@:s var lightBack : Float = 0.;
	@:s var lightPower : Float = 1.;
	@:s var transitionSpeed : Float = 1.;
	@:s var useLightZ : Bool = true;

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
			var lightDir = mainLight.getAbsPos().front();
			var camDir = r.ctx.camera.target.sub(r.ctx.camera.pos);
			if( !useLightZ ) {
				lightDir.z = 0;
				camDir.z = 0;
			}
			lightDir.normalize();
			camDir.normalize();
			var dir = (lightDir.dot(camDir) + 1) * 0.5;
			exp += hxd.Math.lerp(lightFront, lightBack, Math.pow(dir, lightPower * lightPower));
		}
		var render = cast(r,h3d.scene.pbr.Renderer);
		var f = 1 - Math.pow(1 - transitionSpeed * transitionSpeed, r.ctx.elapsedTime * 60);
		render.exposure = hxd.Math.lerp(render.exposure, exp, f);
	}

	#if editor
	override function edit( ctx : hide.prefab2.EditContext ) {
		var pr = ctx.properties.add(new hide.Element('
			<dl>
			<dt>Light Front</dt><dd><input type="range" min="-2" max="2" field="lightFront"/></dd>
			<dt>Light Back</dt><dd><input type="range" min="-2" max="2" field="lightBack"/></dd>
			<dt>Light Power</dt><dd><input type="range" min="0" max="3" field="lightPower"/></dd>
			<dt>Use Light-Z</dt><dd><input type="checkbox" field="useLightZ"/></dd>
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

	static var _ = Prefab.register("rfx.autoexp", AutoExposure);

}