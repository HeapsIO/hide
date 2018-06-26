package hide.tools;

class RendererSupport {
	
	public function getS3D() : h3d.scene.Scene {
		throw "TODO";
		return null;
	}
	
	public function lookupShader<T:hxsl.Shader>( current : T, ?passName : String ) : T {
		throw "TODO";
		return null;
	}
	
	public static function get() : RendererSupport {
		throw "TODO";
		return null;
	}
		
}