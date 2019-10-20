package monaco;

extern class Model {
	function updateOptions( opts : {?insertSpaces:Bool,?tabSize:Int,?trimAutoWhitespace:Bool} ) : Void;
	function getValueInRange( pos : { startLineNumber : Int, startColumn : Int, endLineNumber : Int, endColumn : Int } ) : String;
}