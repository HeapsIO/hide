package hrt.shgraph;

class ShaderException {

	public var msg : String;
	public var idBox : Int;

	public function new( msg, idBox) {
		this.msg = msg;
		this.idBox = idBox;
	}

	public function toString() {
		return 'ShaderException : ${msg} @${idBox}';
	}

	public static function t( msg : String, idBox : Int) : Dynamic {
		throw new ShaderException(msg, idBox);
		return null;
	}
}