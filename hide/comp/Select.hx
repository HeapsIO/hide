package hide.comp;
using Lambda;

class Select extends Component {

	// The id in the choices list that correspond to the current value
	public var value(default, set) : String;
	var choices : Array<hide.comp.Dropdown.Choice> = null;
	var isClearable : Bool = false;

	function set_value(v:String) {
		value = v;
		if (value == null || value == "") {
			element.val("--- Choose ---");
		} else {
			element.val(choices.find((e) -> e.id == value).text);
		}
		return value;
	}

	public function new(?parent,?root, choices: Array<hide.comp.Dropdown.Choice>, isClearable : Bool = true) {
		if (root == null)
			root = new Element('<input value="--- Choose ---">');
		super(parent, root);

		this.choices = choices;
		value = null;

		this.isClearable = isClearable;
		if (isClearable) {
			this.choices.unshift({id : "", text : "--- Clear ---", classes : ["compact"]});
		}

		element.toggleClass("file", true);
		element.contextmenu(function(e: js.jquery.Event) {
			e.preventDefault();
			onContextmenu(e);
			return false;
		});
		element.mousedown(function(e) {
			e.preventDefault();
			if (e.button == 0) {
				var d = new hide.comp.Dropdown(new Element(element), choices, value, (_) -> null, true);
				d.ignoreIdInSearch = true;
				d.onSelect = function(v) {
					change(v);
				}
			}
		});
	}

	public dynamic function onContextmenu(e: js.jquery.Event) {
		var options = [
			{ label : "Copy", click : () -> ide.setClipboard(value)},
			{ label : "Paste", click : () -> change(ide.getClipboard())},
		];
		if (isClearable) {
			options.unshift({ label : "Clear", click : () -> change("")});
		}
		ContextMenu2.createFromEvent(cast e, options);
	}

	function change(newId : String) {
		value = newId;
		onChange(newId);
	}

	public dynamic function onChange(newId : String) {

	}
}