package hrt.prefab.l3d.modellibrary;

import hrt.prefab.l3d.modellibrary.ModelLibrary.BakedMaterialData;

@:access(hrt.prefab.l3d.modellibrary.Batcher)
@:access(hrt.prefab.l3d.modellibrary.ModelLibrary)
class MeshEmitter {
	var bakedMaterials : Array<BakedMaterialData>;
	var primitive : h3d.prim.HMDModel;
	var materials : Array<h3d.mat.Material>;

	static function createFromMesh(bakedMaterials : Array<BakedMaterialData>, mesh : h3d.scene.Mesh) {
		var multimat = Std.downcast(mesh, h3d.scene.MultiMaterial);
		var materials = multimat != null ? multimat.materials : [mesh.material];
		return new MeshEmitter(bakedMaterials, cast(mesh.primitive), materials);
	}

	function new(bakedMaterials : Array<BakedMaterialData>, primitive : h3d.prim.HMDModel, materials : Array<h3d.mat.Material> ) {
		this.bakedMaterials = bakedMaterials;
		this.primitive = primitive;
		this.materials = materials;
	}

	function emitInstance( batcher : Batcher, ?absPos : h3d.Matrix, ?cb : h3d.scene.MeshBatch -> Void ) {
		for ( materialIndex => bakedMaterial in bakedMaterials ) {
			var batch = batcher.getBatch(bakedMaterial, materialIndex, this);
			batcher.library.emitInstance(bakedMaterial, primitive, batch, absPos);
			if ( cb != null )
				cb(batch);
		}
	}
}