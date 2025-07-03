package hide.comp.cdb;

@:access(hide.comp.cdb.Table)
class Separator extends Component {
	public static var SEPARATOR_KEY = "sep";

	public var table : Table;
	public var data : cdb.Data.Separator;
	public var parent : Separator;
	public var subs : Array<Separator> = [];

	var visible(get, null) : Bool; // Is the separator visible (i.e. parent separators aren't collapsed )
	var filtered : Bool = false;
	var expanded : Bool = true;

	public function new(root : Element, table: Table, data : cdb.Data.Separator) {
		this.table = table;
		this.data = data;
		this.saveDisplayKey = SEPARATOR_KEY;

		var e = new Element('<tr class="separator">
			<td colspan="${table.columns.length + 1}">
				<a href="#" class="toggle"></a>
				<span></span>
			</td>
		</tr>');

		super(root, e);

		var toggleBtn = e.find("a");
		var content = e.find("span");
		if( data.title != null )
			e.addClass(StringTools.replace('separator-${data.title}'.toLowerCase(), " ", "-"));

		refresh();

		element.contextmenu(function(e) {
			var allowedParents : Array<Separator> = [];

			var allowedParent = this.parent;
			while (allowedParent != null) {
				allowedParents.push(allowedParent);
				allowedParent = allowedParent.parent;
			}

			allowedParents.push(null);
			allowedParents.reverse();

			var siblings = [];
			if (this.parent == null) {
				for (s in table.separators) {
					if (s.parent == null)
						siblings.push(s);
				}
			}
			else {
				siblings = this.parent.subs;
			}

			if (siblings.length > 1 && siblings[0] != this) {
				var prevSibling = siblings[siblings.indexOf(this) - 1];
				allowedParents.push(prevSibling);
			}

			var opts : Array<hide.comp.ContextMenu.MenuItem> = [
				{ label : "Expand", click : function() expand() },
				{ label : "Collapse", click : function() collapse() },
				{
					label : "Parent",
					enabled : allowedParents.length > 1,
					menu : [for( p in allowedParents ) {
						var level = p == null ? -1 : p.data.level == null ? -1 : p.data.level;
						{
							label : p == null ? "(None)" : [for ( i in 0...(level + 1)) ""].join("  ")+p.data.title,
							checked : p == this.parent,
							click : function() {
								table.editor.beginChanges();

								function rec(s : Separator, newLevel : Int) {
									s.data.level = newLevel;
									for (sub in s.subs)
										rec(sub, newLevel + 1);
								}

								var newLevel : Int = p == null ? -1 : p.data.level == null ? 1 : p.data.level + 1;
								rec(this, newLevel);
								table.editor.endChanges();
								table.refresh();
							},
						}
					}]
				},
				{ label : "", isSeparator : true },
				{ label : "Expand All", click : function() {
					for (s in table.separators)
						s.expand();
				}},
				{ label : "Collapse All", click : function() {
					for (s in table.separators)
						s.collapse();
				}},
				{ label : "", isSeparator : true },
				{ label : "Expand Children", click : function() {
					function rec(s : Separator) {
						s.expand();
						for (sub in s.subs)
							sub.expand();
					}
					rec(this);
				}},
				{ label : "Collapse Children", click : function() {
					function rec(s : Separator) {
						s.collapse();
						for (sub in s.subs)
							sub.collapse();
					}
					rec(this);
				}},
				{ label : "Collapse Others", click : function() {
					var ignoreList = [this];
					var parent = this.parent;
					while(parent != null) {
						ignoreList.push(parent);
						parent = parent.parent;
					}

					for (s in table.separators)
						if (!ignoreList.contains(s))
							s.collapse();
				}},
				{ label : "", isSeparator : true },
				{ label : "Remove", enabled : !table.sheet.props.hide, click : function() {
					table.editor.beginChanges();
					table.sheet.separators.splice(@:privateAccess table.separators.indexOf(this), 1);
					table.editor.endChanges();
					table.editor.refresh();
				}}
			];
			#if js
			if( data.path != null )
				opts.unshift({
					label : "Open",
					click : function() {
						ide.openFile(data.path);
					},
				});
			#end
			hide.comp.ContextMenu.createFromPoint(ide.mouseX, ide.mouseY, opts);
		});

		element.dblclick(function(e) {
			if( !table.canInsert() ) return;
			content.empty();
			new Element("<input>").appendTo(content).focus().val(data.title == null ? "" : data.title).blur(function(e) {
				var newTitle = Element.getVal(e.getThis());
				var prevTitle = data.title;
				e.getThis().remove();

				table.editor.beginChanges();
				if( newTitle == "" ) newTitle = null;
				if( newTitle == null )
					Reflect.deleteField(data, "title");
				else
					data.title = newTitle;

				if (prevTitle != null && newTitle == null)
					data.level = data.level == null ? data.level = 1 : data.level + 1;
				else if (prevTitle == null && newTitle != null)
					data.level = data.level == 1 ? null : data.level - 1;

				if (data.level == null)
					Reflect.deleteField(data, "level");

				table.editor.endChanges();
				table.refresh();

				var l = getLines();
				if( l.length > 0 ) {
					if( l[0].cells.length > 0 )
						l[0].cells[0].focus();
				}
			}).keypress(function(e) {
				e.stopPropagation();
			}).keydown(function(e) {
				if( e.keyCode == 13 ) { e.getThis().blur(); e.preventDefault(); } else if( e.keyCode == 27 ) content.text(data.title);
				e.stopPropagation();
			});
		});

		toggleBtn.dblclick(function(e) e.stopPropagation());
		toggleBtn.click((e) -> toggle());
	}

	public function refresh(refreshChildren : Bool = true) {
		expanded = getDisplayState(getSeparatorKey());
		if (expanded == null) expanded = true;

		var content = element.find("span");
		var toggle = element.find("a");

		toggle.toggle(data.title != null);
		toggle.text(expanded ? "🡇" : "🡆");

		function getLineCountRec(s : Separator) : Int {
			var count = s.getLines().length;
			for (sub in s.subs)
				count += getLineCountRec(sub);

			return count;
		}

		content.text(data.title == null ? "" : data.title+(expanded ? "" : " ("+getLineCountRec(this)+")"));
		element.toggleClass("sep-hidden", !visible);

		var lines = getLines();
		for (l in lines) {
			var visible = getLinesVisiblity();
			if (!visible) {
				l.hide();
				continue;
			}

			if (visible && (l.element == null || l.element.get(0).classList.contains("hidden")))
				l.create();
		}

		element.attr("level", data.level == null ? 0 : data.level);
		element.removeClass("seplevel-"+(data.level == null ? 0 : data.level));
		element.addClass('seplevel-'+(data.level == null ? 0 : data.level));

		if (refreshChildren) {
			for (s in subs)
				s.refresh();
		}
	}


	public function toggle() {
		if (this.expanded)
			collapse();
		else
			expand();
	}

	public function expand() {
		setState(true);
	}

	public function collapse() {
		setState(false);
	}

	public function reveal() {
		var s = this;
		while (s != null) {
			s.expand();
			s = s.parent;
		}
	}

	function setState(expand : Bool) {
		if (expand == this.expanded)
			return;

		expanded = expand;
		saveDisplayState(getSeparatorKey(), expanded);
		refresh();
	}


	public static function getParentSeparators(lineIdx : Int, separators : Array<Separator> ) : Array<Separator> {
		var res = [];
		var idx = separators.length - 1;
		while (idx >= 0) {
			if (separators[idx].data.index <= lineIdx && ((idx + 1) >= separators.length || separators[idx + 1].data.index > lineIdx)) {
				res.push(separators[idx]);
				break;
			}
			idx--;
		}

		if (res.length == 0)
			return res;

		while (res[0].parent != null)
			res.insert(0, res[0].parent);
		return res;
	}

	public function getLinesVisiblity() {
		return visible && expanded && !filtered;
	}

	function get_visible() {
		if (parent == null)
			return !filtered;
		return parent.visible && parent.expanded && !filtered;
	}

	public function getLines() {
		var sIdx = @:privateAccess table.separators.indexOf(this);
		var startIdx = data.index;
		var endIdx = sIdx < table.sheet.separators.length - 1 ? table.sheet.separators[sIdx + 1].index : table.sheet.lines.length;
		return [for (idx in startIdx...endIdx) table.lines[idx]];
	}

	function getSeparatorKey() : String {
		var key = this.data.title;

		var parent = this.parent;
		while(parent != null) {
			key = '${parent.getSeparatorKey()}/$key';
			parent = parent.parent;
		}

		return key;
	}
}