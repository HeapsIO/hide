package hrt.prefab.l3d.modellibrary;

import hrt.prefab.l3d.modellibrary.ModelLibrary.BakedMaterialData;
import h3d.mat.PbrMaterial.PbrProps;

@:access(hrt.prefab.l3d.modellibrary.ModelLibrary)
@:access(hrt.prefab.l3d.modellibrary.MeshEmitter)
class Batcher extends h3d.scene.Object {
	public var library : ModelLibrary;
	public var isStatic : Bool = false;

	var batches: Array<h3d.scene.MeshBatch>;

	function new(parent : h3d.scene.Object, library : ModelLibrary) {
		super(parent);
		this.library = library;
		batches = [];
	}

	public function iterateBatches(f : h3d.scene.MeshBatch -> Void) {
		for ( b in batches )
			if ( b != null )
				f(b);
	}

	public function emitInstance(mesh : h3d.scene.Mesh, absPos : h3d.Matrix, emitCountTip : Int = -1, ?cb : h3d.scene.MeshBatch -> Void) {
		var meshEmitter = library.getMeshEmitter(mesh);
		meshEmitter.emitInstance(this, absPos, emitCountTip, cb);
	}

	public function defaultCreateMeshBatch(?props : PbrProps, ?material : h3d.mat.Material) {
		var batch = new h3d.scene.MeshBatch(library.cache.hmdPrim, null, this);
		setupMeshBatch(batch, props, material);
		return batch;
	}

	public dynamic function createMeshBatch(batcher : Batcher, ?props : PbrProps, ?material : h3d.mat.Material) {
		return defaultCreateMeshBatch(props, material);
	}

	function getBatch( bakedMaterial : BakedMaterialData, materialIndex : Int, meshEmitter : MeshEmitter ) {
		var batch = batches[bakedMaterial.materialConfig];
		if ( batch == null ) {
			var material = meshEmitter.materials[materialIndex];
			var pbrProps = (material.props:PbrProps);
			batch = createMeshBatch(this, pbrProps, material);
			batches[bakedMaterial.materialConfig] = batch;
		}
		return batch;
	}

	public function setupMeshBatch(batch : h3d.scene.MeshBatch, ?props : PbrProps, ?material : h3d.mat.Material ) {
		if ( material != null ) {
			for ( s in material.mainPass.getShaders())
				if ( !library.isForbiddenShader(s) ) {
					var shader = batch.material.mainPass.getShader(Type.getClass(s));
					if ( shader == null || (s.toString() != shader.toString()))
						batch.material.mainPass.addShader(s);
				}
			for ( s in @:privateAccess material.mainPass.selfShaders )
				if ( !library.isForbiddenShader(s) ) {
					var shader = batch.material.mainPass.getShader(Type.getClass(s));
					if ( shader == null || (s.toString() != shader.toString()))
						@:privateAccess batch.material.mainPass.addSelfShader(s);
				}
		}

		if ( isStatic ) {
			batch.material.staticShadows = true;
			batch.fixedPosition = true;
		}
		batch.cullingCollider = this.cullingCollider;
		batch.name = "modelLibrary";
		batch.material.mainPass.addShader(library.cache.shader);
		if ( props != null ) {
			batch.material.props = props;
			batch.material.refreshProps();
			if ( (batch.material.props:PbrProps).alphaKill && batch.material.textureShader == null )
				batch.material.mainPass.addShader(library.killAlpha);
		}
	}

	override function onRemove() {
		super.onRemove();
		for ( b in batches )
			b.remove();
		batches = [];
	}
}