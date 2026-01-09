package hide;

class Ide extends hide.tools.IdeData {
	public static var inst : Ide;

	public override function new() {
		super();
		inst = this;
	}
}