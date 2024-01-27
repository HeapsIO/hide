package hide.comp;

typedef ContextMenuItem = {
	var label : String;
	@:optional var menu : Array<ContextMenuItem>;
	@:optional var click : Void -> Void;
	@:optional var enabled : Bool;
	@:optional var checked : Bool;
	@:optional var isSeparator : Bool;
	@:optional var icon : String;
	@:optional var stayOpen : Bool;
	@:optional var keys : String;
}

class ContextMenu {

	static var CTX_ANCHOR : Element;
	static final CONTEXTMENU_LAYER = 900;

	public function new( config : Array<ContextMenuItem> ) {
		var ide = hide.Ide.inst;
		#if js
		var args = {
			selector: '#ctx-menu-anchor',
			trigger: "none",
			items: makeMenu(config),
			position: (opt, x, y) -> {
				opt.$menu.css({ left: ide.mouseX, top: ide.mouseY });
			},
			zIndex: CONTEXTMENU_LAYER + 2,
			useModal: false,
			scrollable: true,
		}
		// wait until mousedown to get correct mouse pos
		haxe.Timer.delay(function() {
			if( CTX_ANCHOR == null ) {
				CTX_ANCHOR = new Element('<div id="ctx-menu-anchor">');
				new Element("body").append(CTX_ANCHOR);
			}
			untyped jQuery.contextMenu('destroy', '#ctx-menu-anchor');
			untyped jQuery.contextMenu(args);
			(CTX_ANCHOR : Dynamic).contextMenu();
		}, 0);
		#end
	}

	public static function hideMenu() {
		if( CTX_ANCHOR != null )
			(CTX_ANCHOR : Dynamic).contextMenu("hide");
	}

	function makeMenu( config : Array<ContextMenuItem> ) {
		var ret : Dynamic = {};
		for( i in 0...config.length ) {
			Reflect.setField(ret, "" + i, makeMenuItem(config[i]));
		}
		return ret;
	}

	function makeMenuItem( i:ContextMenuItem ) : Dynamic {
		if( i.isSeparator) {
			return {
				type: "cm_separator",
			};
		}
		var name = "";
		if( i.icon != null && i.checked == null)
			name += '<span class="context-icon"><span class="ico ico-${i.icon}"></span></span>';
		name += i.label;
		if( i.keys != null ) {
			name += '<span class="contextmenu-keys">' + toKeyString(i.keys) + "</span>";
		}
		var autoclose = (i.stayOpen == null) ? true : !i.stayOpen;
		var emptySubMenu = i.menu != null && i.menu.length <= 0;
		var ret : Dynamic = {
			name : name,
			isHtmlName : true,
			callback : function(itemKey, opt, rootMenu, originalEvent) {
				i.click();
				return autoclose;
			},
			disabled : (i.enabled == null ? false : !i.enabled) || emptySubMenu,
			items : (i.menu == null || emptySubMenu) ? null : makeMenu(i.menu),
		};
		if( i.checked != null ) {
			ret.type = 'checkbox';
			ret.selected = i.checked;
			ret.events = {
				change : function(event) {
					if( autoclose )
						hideMenu();
					i.click();
				},
			};
		}
		return ret;
	}

	function toKeyString( keyCode : String ) {
		return keyCode.split("-").join("+");
	}

}