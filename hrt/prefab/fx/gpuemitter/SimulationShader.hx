package hrt.prefab.fx.gpuemitter;

class SimulationShader extends hrt.prefab.Shader {

	override function applyShader(obj : h3d.scene.Object, mat : h3d.mat.Material, sh : hxsl.Shader) {
		var gpuEmitter = Std.downcast(obj, hrt.prefab.fx.gpuemitter.GPUEmitter.GPUEmitterObject);
		if ( gpuEmitter == null )
			return;
		var prevSh = gpuEmitter.simulationPass.getShader(Type.getClass(sh));
		if ( prevSh != null )
			gpuEmitter.simulationPass.removeShader(prevSh);
		gpuEmitter.simulationPass.addShader(sh);
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