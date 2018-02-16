package hide.ui;

enum HistoryElement {
	Field( obj : Dynamic, field : String, oldValue : Dynamic );
	Array( obj : Array<Dynamic>, field : Int, oldValue : Dynamic );
	Custom( undoRedo : Bool -> Void );
}

private typedef Elt = { h : HistoryElement, id : Int, callb : Void -> Void };

class UndoHistory {

	var uidGen = 0;
	var undoElts : Array<Elt> = [];
	var redoElts : Array<Elt> = [];
	public var currentID(get, never) : Int;

	public function new() {
	}

	function get_currentID() {
		return undoElts.length == 0 ? 0 : undoElts[undoElts.length - 1].id;
	}

	public function change(h, ?callb) {
		undoElts.push({ h : h, id : ++uidGen, callb : callb });
		redoElts = [];
		onChange();
	}

	public function undo() {
		var h = undoElts.pop();
		return handleElement(h, redoElts);
	}

	public function redo() {
		var h = redoElts.pop();
		return handleElement(h, undoElts);
	}

	public function handleElement( e : Elt, other : Array<Elt> ) {
		if( e == null ) return false;
		switch( e.h ) {
		case Field(obj, field, value):
			var curValue = Reflect.field(obj, field);
			other.push({ h : Field(obj, field, curValue), id : e.id, callb : e.callb });
			Reflect.setProperty(obj, field, value);
		case Array(arr, index, value):
			var curValue = arr[index];
			other.push({ h : Array(arr, index, curValue), id : e.id, callb : e.callb });
			arr[index] = value;
		case Custom(f):
			other.push(e);
			f(other == redoElts);
		}
		if( e.callb != null ) e.callb();
		onChange();
		return true;
	}

	public dynamic function onChange() {
	}

}