package monaco;

@:native("monaco.editor")
extern class ScriptEditor {


	function addCommand( command : Int, callback : Void -> Void ) : Void;
	function getValue( ?options : { ?lineEnding : String, ?preserveBOM : Bool } ) : String;
	function onDidChangeModelContent( listener : Void -> Void ) : Void;
	function onDidBlurEditorText( listener : Void -> Void ) : Void;
	function onDidFocusEditorText( listener : Void -> Void ) : Void;
	function focus() : Void;
	function dispose() : Void;
	function getModel() : Model;
	function deltaDecorations( old : Array<String>, newDeco : Array<ModelDeltaDecoration> ) : Array<String>;
	function setValue( script : String ) : Void;
	function updateOptions( options : Dynamic ) : Void;
	function getPosition() : Position;
	function setPosition( p : Position ) : Void;

	public static function create( elt : js.html.Element, ?options : Dynamic ) : ScriptEditor;

}
