package hide.view.l3d;

class ProbeBakerProcess {

	static var lightProbeBaker : h3d.scene.pbr.LightProbeBaker;
	static var bakeTime = 0.01;
	static var lastlightmapBaked : hide.prefab.l3d.VolumetricLightmap;
	static var globalRemainingTime : Float;

	public var progress : Float = 0.;
	var volumetricLightmap : hide.prefab.l3d.VolumetricLightmap;
	var s3d : h3d.scene.Scene;

	public function new(s3d, volumetricLightmap){
		progress = 0;
		this.s3d = s3d;
		this.volumetricLightmap = volumetricLightmap;

		if(lightProbeBaker == null){
			lightProbeBaker = new h3d.scene.pbr.LightProbeBaker();
			lightProbeBaker.useGPU = false;
		}

		var rend = Std.instance(s3d.renderer, h3d.scene.pbr.Renderer) ;
		if(rend != null) lightProbeBaker.environment = rend.env;
	}

	public function update(dt:Float){

		if(lastlightmapBaked == volumetricLightmap)
			globalRemainingTime = bakeTime;

		if(lastlightmapBaked == null){
			lastlightmapBaked = volumetricLightmap;
		}

		if(lastlightmapBaked == volumetricLightmap && globalRemainingTime > 0){
			var remainingTime = lightProbeBaker.bakePartial(s3d.renderer, s3d, volumetricLightmap.volumetricLightmap, 32, bakeTime);
			globalRemainingTime -= remainingTime;
			volumetricLightmap.volumetricLightmap.packDataInsideTexture();
			volumetricLightmap.createPreview();
			progress = (volumetricLightmap.volumetricLightmap.lastBakedProbeIndex +1.0) /volumetricLightmap.volumetricLightmap.lightProbes.length;

			if(progress == 1){
				lastlightmapBaked = null;
			}
		}
	}
}

