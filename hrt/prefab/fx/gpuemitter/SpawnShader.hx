package hrt.prefab.fx.gpuemitter;

class SpawnShader extends hrt.prefab.Shader {

	override function applyShader(obj : h3d.scene.Object, mat : h3d.mat.Material, sh : hxsl.Shader) {
		var gpuEmitter = Std.downcast(obj, GPUEmitter.GPUEmitterObject);
		if ( gpuEmitter == null )
			return;
		var prevSh = gpuEmitter.spawnPass.getShader(Type.getClass(sh));
		if ( prevSh != null )
			gpuEmitter.spawnPass.removeShader(prevSh);
		gpuEmitter.spawnPass.addShader(sh);
	}

	#if editor
	override function getHideProps() : hide.prefab.HideProps {
		var name = Type.getClassName(Type.getClass(this)).split(".").pop();
		return { icon : "asterisk",
		name : name,
		allowParent : function(p) return p.to(GPUEmitter) != null
		};
	}
	#end
}