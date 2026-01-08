package monaco;

extern class Range {
	var startColumn : Int;
	var endColumn : Int;
	var startLineNumber : Int;
	var endLineNumber : Int;
	public function new(startLineNumber: Int, startColumn: Int, endLineNumber: Int, endColumn: Int) : Void;
}