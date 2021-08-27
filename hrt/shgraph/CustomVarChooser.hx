package hrt.shgraph;

using hxsl.Ast;

#if editor
// TODO block or raise an error on illegal names
class CustomVarChooser extends hide.comp.Component {
	public var variable : TVar = null;

	public function new(?parent : hide.Element, ?initialName : String, ?initialType : Type, onChange : (TVar) -> Void) {
		var el = new hide.Element('<div class="custom-var">
			<div class="custom-var-row">
				<label for="customName">Name</label><span><input type="text" id="customName"/></span>
			</div>
			<div class="custom-var-row">
				<label for="customType">Type</label><span><select id="customType"></select></span>
			</div>
		</div>');
		super(parent, el);

		var textInput = element.find("#customName");
		var select = element.find("#customType");
		var availableTypes = [
			"Color" => TVec( 4, VFloat ),
			"Int" => TInt,
			"Bool" => TBool,
			"Float" => TFloat,
			"String" => TString,
			"Vec2" => TVec( 2, VFloat ),
			"Vec3" => TVec( 3, VFloat ),
		];
		for( key => value in availableTypes ) {
			select.append(new hide.Element('<option value="${key}">${key}</option>'));
			if( value == initialType )
				select.val(key);
		}
		if( initialName != null ) {
			textInput.val(initialName);
		}
		if( initialName != null && initialName != "" && initialType != null ) {
			variable = {
				parent: null,
				id: 0,
				kind: Local,
				name: initialName,
				type: availableTypes[select.val()],
			};
		}
		function changedFun(_) {
			var name = textInput.val();
			if( name == "" )
				return;
			variable = {
				parent: null,
				id: 0,
				kind: Local,
				name: name,
				type: availableTypes[select.val()],
			};
			onChange(variable);
		}
		select.on("change", changedFun);
		textInput.on("change", changedFun);
	}

	public function show() {
		element.show();
	}

	public function hide() {
		element.hide();
	}
}
#end
