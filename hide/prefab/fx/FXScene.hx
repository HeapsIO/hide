package hide.prefab.fx;

class FXScene extends Library {

	public function new() {
		super();
		type = "fx";
	}

	override function save() {
		var obj : Dynamic = super.save();
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
	}

	override function edit( ctx : EditContext ) {
		#if editor
		var props = new hide.Element('
			<div class="group" name="Level">
			</div>
		');
		ctx.properties.add(props, this, function(pname) {
			ctx.onChange(this, pname);
		});
		#end
	}

	override function getHideProps() {
		return { icon : "cube", name : "FX", fileSource : ["fx"] };
	}

	static var _ = Library.register("fx", FXScene);
}