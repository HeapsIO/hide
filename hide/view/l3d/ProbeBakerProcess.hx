package hide.view.l3d;

class ProbeBakerProcess {

	public var progress : Float = 0.;

	var lightProbeBaker : h3d.scene.pbr.LightProbeBaker;
	var volumetricLightmap : hide.prefab.l3d.VolumetricLightmap;
	var s3d : h3d.scene.Scene;
	var bakeTime : Float;
	var resolution : Int;

	public function new(s3d, volumetricLightmap, res, bakeTime : Float = 0.08 ){
		progress = 0;
		this.s3d = s3d;
		this.bakeTime = bakeTime;
		this.volumetricLightmap = volumetricLightmap;
		this.resolution = res;

		lightProbeBaker = new h3d.scene.pbr.LightProbeBaker();
		lightProbeBaker.useGPU = false;

		var rend = Std.instance(s3d.renderer, h3d.scene.pbr.Renderer) ;
		if(rend != null) {
			lightProbeBaker.environment = rend.env;
			if( rend.env == null || rend.env.env == null || rend.env.env.isDisposed() ) trace("Environment missing");
		 } else
		 	trace("Invalid renderer");
	}

	public function update(dt:Float) {
		lightProbeBaker.bake(s3d, volumetricLightmap.volumetricLightmap, resolution, bakeTime);
		volumetricLightmap.createDebugPreview();
		progress = (volumetricLightmap.volumetricLightmap.lastBakedProbeIndex +1.0) / volumetricLightmap.volumetricLightmap.getProbeCount();
		if( progress == 1 ) {
			lightProbeBaker.dispose();
			lightProbeBaker = null;
			onEnd();
		}
	}

	public dynamic function onEnd() {
	}

}

