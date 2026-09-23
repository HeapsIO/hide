package hrt.prefab.rfx;

class HierarchicalSSR extends RendererFX {

	@:s var stepCount : Int = 64;
	@:s var fadeInExponent : Float = 0.2;
	@:s var fadeOutExponent : Float = 2.0;
	@:s var depthTolerance : Float = 0.5;
	@:s var distanceBias : Float = 0.0;
	@:s var distancePowerBias : Float = 1.0;
	@:s var marginSize : Float = 0.1;

	@:s var debugEnabled : Bool = false;
	@:s var debugRoughnessFactor : Float = 1.0;
	@:s var debugIteration : Int = 0;

	var ssr = new h3d.pass.SSR();

	override function end( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
		#if !editor
		var r = Std.downcast(r, h3d.scene.pbr.Renderer);
		if( step == Forward && r != null && checkEnabled() ) {
			ssr.stepCount = stepCount;
			ssr.fadeInExponent = fadeInExponent;
			ssr.fadeOutExponent = fadeOutExponent;
			ssr.depthTolerance = depthTolerance;
			ssr.distanceBias = distanceBias;
			ssr.distancePowerBias = distancePowerBias;
			ssr.marginSize = marginSize;
			ssr.debugEnabled = debugEnabled;
			ssr.debugRoughnessFactor = debugRoughnessFactor;
			ssr.debugIteration = debugIteration;
			ssr.apply(r);
		}
		#end
	}

	override function edit2( ctx : hrt.prefab.EditContext2 ) {
		ctx.build(
			<root>
				<category("SSR")>
					<range(1, 64) int field={stepCount}/>
					<slider min={0.0} field={fadeInExponent}/>
					<slider min={0.0} field={fadeOutExponent}/>
					<slider min={0.0} field={depthTolerance}/>
					<slider min={0.0} field={distanceBias}/>
					<slider min={0.0} field={distancePowerBias}/>
					<range(0.0, 1.0) field={marginSize}/>
				</category>
				<category("Debug")>
					<checkbox label="Enable debug" field={debugEnabled}/>
					<range(0.0, 1.0) label="Roughness factor" field={debugRoughnessFactor}/>
					<slider int field={debugIteration}/>
				</category>
			</root>
		);
	}

	static var _ = Prefab.register("rfx.hierarchicalSSR", HierarchicalSSR);

}
