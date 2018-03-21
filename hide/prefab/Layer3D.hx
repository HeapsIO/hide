package hide.prefab;

class Layer3D extends Object3D {

    public var locked = false;
    public var color = 0xffffffff;
	
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
		'),this);
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
                    ctx.onChange(this);
                }));
                ctx.onChange(this);
            }
        }
        #end
    }
    
	override function getHideProps() {
		return { icon : "file", name : "Layer", fileSource : null };
	}

	static var _ = Library.register("layer", Layer3D);
}