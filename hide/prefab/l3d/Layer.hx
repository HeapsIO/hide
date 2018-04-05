package hide.prefab.l3d;
using Lambda;

class Layer extends Object3D {

	public var locked = false;
	public var color = 0xffffffff;

	public function new(?parent) {
		super(parent);
		type = "layer";
	}

	public function getCdbModel() {
		var levelSheet = getLevelSheet();
		if(levelSheet == null) return null;
		var lname = name.toLowerCase();
		lname = lname.split("_")[0].split(" ")[0].split("-")[0];
		var col = levelSheet.columns.find(c -> { var lc = c.name.toLowerCase(); lc == lname || lc + "s" == lname; });
		if(col == null || col.type != TList) return null;
		return levelSheet.getSub(col);
	}

	public function getLevelSheet() {
		var ide = hide.ui.Ide.inst;
		return ide.database.getSheet(ide.currentProps.get("l3d.cdbLevel", "level"));
	}
	
	override function save() {
		var obj : Dynamic = super.save();
		obj.locked = locked;
		obj.color = color;
		return obj;
	}

	override function load( obj : Dynamic ) {
		super.load(obj);
		locked = obj.locked;
		color = obj.color;
	}

	override function edit( ctx : EditContext ) {
		super.edit(ctx);
		#if editor
		var props = ctx.properties.add(new hide.Element('
			<div class="group" name="Layer">
				<dl>
					<dt>Locked</dt><dd><input type="checkbox" field="locked"/></dd>
					<dt>Color</dt><dd><input name="colorVal"/></dd>
				</dl>
			</div>
		'),this, function(pname) {
			ctx.onChange(this, pname);
		});
		var colorInput = props.find('input[name="colorVal"]');
		var picker = new hide.comp.ColorPicker(colorInput, false);
		picker.value = color;
		picker.onChange = function(move) {
			if(!move) {
				var prevVal = color;
				var newVal = picker.value;
				color = picker.value;
				ctx.properties.undo.change(Custom(function(undo) {
					if(undo) {
						color = prevVal;
					}
					else {
						color = newVal;
					}
					picker.value = color;
					ctx.onChange(this, "color");
				}));
				ctx.onChange(this, "color");
			}
		}
		#end
	}
	
	override function getHideProps() {
		return { icon : "file", name : "Layer", fileSource : null };
	}

	static var _ = Library.register("layer", Layer);
}