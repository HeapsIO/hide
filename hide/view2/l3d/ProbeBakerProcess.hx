package hide.view2.l3d;

class ProbeBakerProcess {

	public var progress : Float = 0.;

	var lightProbeBaker : hide.view2.l3d.LightProbeBaker;
	var volumetricLightmap : hrt.prefab2.vlm.VolumetricLightmap;
	var bakeTime : Float;
	var resolution : Int;

	public function new(volumetricLightmap, res, useGPU, bakeTime = 0.016 ){
		progress = 0;
		this.bakeTime = bakeTime;
		this.volumetricLightmap = volumetricLightmap;
		this.resolution = res;
		lightProbeBaker = new hide.view2.l3d.LightProbeBaker();
		lightProbeBaker.useGPU = useGPU;
	}

	public function init( env : h3d.scene.pbr.Environment, sceneData : hrt.prefab2.Prefab, scene : hide.comp2.Scene) {
		lightProbeBaker.initScene(sceneData, scene, env);
	}

	public function update(dt:Float) {
		lightProbeBaker.bake(volumetricLightmap.volumetricLightmap, resolution, bakeTime);
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
