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

	var ssrResolve : h3d.pass.ScreenFx<h3d.shader.pbr.SSR.SSRResolve>;
	var ssrFilter :  h3d.pass.ScreenFx<h3d.shader.pbr.SSR.SSRFilter>;
	var ssrShader : h3d.shader.pbr.SSR;
	var copyPass : h3d.pass.Copy;

	function new(parent, shared) {
		super(parent, shared);
		ssrResolve = new h3d.pass.ScreenFx(new h3d.shader.pbr.SSR.SSRResolve());
		ssrFilter = new h3d.pass.ScreenFx(new h3d.shader.pbr.SSR.SSRFilter());
		ssrFilter.shader.invSize = new h3d.Vector();
		ssrShader = new h3d.shader.pbr.SSR();
		ssrShader.screenSize = new h3d.Vector();
		copyPass = new h3d.pass.Copy();
	}

	function execute( r : h3d.scene.pbr.Renderer, step : h3d.impl.RendererFX.Step ) {
		if ( !checkEnabled() )
			return;

		var ctx = r.ctx;
		r.mark("SSR");

		var hdr = @:privateAccess r.textures.hdr;
		var normal = @:privateAccess r.textures.normal;
		var roughness = @:privateAccess r.textures.pbr;
		var hzb = r.computeHZB();

		var width = hdr.width;
		var height = hdr.height;

		var ssrTarget = r.allocTarget("SSR", false, 1.0, RGBA16F, [Writable, MipMapped, ManualMipMapGen]);
		var ssrTargetCopy = r.allocTarget("SSRCopy", false, 1.0, RGBA16F, [Writable, MipMapped, ManualMipMapGen]);
		var ssrMipLevels = r.allocTarget("SSRMipLevels", false, 1.0, R8, [Writable, MipMapped, ManualMipMapGen]);
		var ssrDebug : h3d.mat.Texture = null;

		ssrTargetCopy.filter = Nearest;
		ssrTargetCopy.mipMap = Nearest;

		ssrShader.DEBUG = debugEnabled;
		if ( debugEnabled ) {
			ssrDebug = r.allocTarget("SSRDebug", false, 1.0, RGBA, [Writable]);
			ssrDebug.clear(0, 0);
			var window = hxd.Window.getInstance();
			ssrShader.debugPixelX = window.mouseX;
			ssrShader.debugPixelY = window.mouseY;
			ssrShader.debugIteration = debugIteration;
			ssrShader.debugRoughnessFactor = debugRoughnessFactor;
			ssrShader.debugSSR = ssrDebug;
		}

		ssrShader.hdrMap = hdr;
		ssrShader.depthMap = hzb;
		ssrShader.normalMap = normal;
		ssrShader.roughnessMap = roughness;
		ssrShader.outputColor = ssrTarget;
		ssrShader.outputMipLevel = ssrMipLevels;

		ssrShader.screenSize.set(width, height);
		ssrShader.mipMaps = hzb.mipLevels;
		ssrShader.stepCount = stepCount;
		ssrShader.fadeInExponent = fadeInExponent;
		ssrShader.fadeOutExponent = fadeOutExponent;
		ssrShader.depthTolerance = depthTolerance;
		ssrShader.distanceBias = distanceBias;
		ssrShader.distancePowerBias = distancePowerBias;
		ssrShader.marginSize = marginSize;
		ssrShader.ORTHOGONAL = ctx.camera.orthoBounds != null;
		ctx.computeDispatch(ssrShader, Std.int((width + 8 - 1) / 8), Std.int((height + 8 - 1) / 8));

		copyPass.shader.texture = ssrTarget;
		ctx.engine.pushTarget(ssrTargetCopy);
		copyPass.render();
		ctx.engine.popTarget();

		var curWidth = width;
		var curHeight = height;
		var mipLevels = ssrTarget.mipLevels;
		// DX12Driver doesn't yet handle transitions at sub-resource level.
		// This means that we cannot bind a mip and use a different one as target.
		// For now, we use a copy as workaround.
		for ( lvl in 1...mipLevels ) {
			var source = lvl & 1 == 0 ? ssrTargetCopy : ssrTarget;
			var target = lvl & 1 == 0 ? ssrTarget : ssrTargetCopy;
			ssrFilter.shader.ssrColor = source;
			ssrFilter.shader.invSize.set(1.0/curWidth, 1.0/curHeight);
			ssrFilter.shader.mipLevel = lvl;
			source.startingMip = lvl - 1;
			ctx.engine.pushTarget(target, 0, lvl);
			ssrFilter.render();
			ctx.engine.popTarget();

			if ( target == ssrTargetCopy ) {
				ssrTargetCopy.startingMip = lvl;
				h3d.pass.Copy.run(ssrTargetCopy, ssrTarget, None, null, 0, lvl);
			}
			ssrTarget.startingMip = lvl;
			ctx.engine.pushTarget(ssrTargetCopy, 0, lvl);
			copyPass.render();
			ctx.engine.popTarget();
			curWidth >>= 1;
			curHeight >>= 1;
		}
		ssrTarget.startingMip = 0;
		ssrTargetCopy.startingMip = 0;

		ssrResolve.shader.ssrMipLevel = ssrMipLevels;
		ssrResolve.shader.ssrColor = ssrTarget;
		ssrResolve.pass.setBlendMode(Alpha);
		ctx.engine.pushTarget(hdr);
		ssrResolve.render();
		ctx.engine.popTarget();

		if ( debugEnabled )
			h3d.pass.Copy.run(ssrDebug, hdr, Alpha);
	}

	override function end( r : h3d.scene.Renderer, step : h3d.impl.RendererFX.Step ) {
		#if !editor
		var r = Std.downcast(r, h3d.scene.pbr.Renderer);
		if( step == Forward && r != null) {
			execute(r, step);
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
