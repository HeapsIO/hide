package hide.comp;

enum HistoryElement {
	Field( obj : Dynamic, field : String, oldValue : Dynamic );
}

private typedef Elt = { h : HistoryElement, callb : Void -> Void };

class UndoHistory {

	var undoElts : Array<Elt> = [];
	var redoElts : Array<Elt> = [];

	public function new() {
	}

	public function change(h, ?callb) {
		undoElts.push({ h : h, callb : callb });
		redoElts = [];
		trace(undoElts.length);
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
			other.push({ h : Field(obj, field, curValue), callb : e.callb });
			Reflect.setField(obj, field, value);
		}
		if( e.callb != null ) e.callb();
		return true;
	}

}