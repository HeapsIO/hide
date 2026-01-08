package monaco;

typedef ModelDeltaDecoration = {
	var range : Range;
	var options : {
		?afterContentClassName : String,
		?beforeContentClassName : String,
		?className : String,
		?glyphMarginClassName : String,
		?glyphMarginHoverMessage : MarkdownString,
		?hoverMessage : MarkdownString,
		?inlineClassName : String,
		?inlineClassNameAffectsLetterSpacing : Bool,
		?isWholeLine : Bool,
		?linesDecorationsClassName : String,
		?marginClassName : String,
		?overviewRuler : Todo,
		?stickiness : Todo,
		?zIndex : Int,
	};
}