package hide.view.l3d;

enum Transform2D {
	Pan;
	Scale;
	ScaleX;
	ScaleY;
	Rotation;
}

class Gizmo2D extends h2d.Object {

	var int : h2d.Interactive;
	var gr : h2d.Graphics;
	var scaleSign = 1;

	public var scaleAmount = 1.01;

	public var onStartMove : Transform2D -> Void;
	public var onMove: { x : Float, y : Float, scaleX : Float, scaleY : Float, rotation : Float } -> Void;
	public var onFinishMove: Void -> Void;
	public var moving(default, null): Bool;

	public function new(?parent) {
		super(parent);
		int = new h2d.Interactive(0,0,this);
		int.propagateEvents = true;
		var cScale = hxd.Cursor.CustomCursor.getNativeCursor("nwse-resize");
		var cScaleX = hxd.Cursor.CustomCursor.getNativeCursor("ew-resize");
		var cScaleY = hxd.Cursor.CustomCursor.getNativeCursor("ns-resize");
		var cRot = hxd.Cursor.CustomCursor.getNativeCursor("grabbing");
		int.onMove = function(e:hxd.Event) {
			if( moving ) return;
			var z = getZone(e);
			switch( z ) {
			case Pan:
				e.cancel = true;
				int.cursor = Button;
			case Scale:
				int.cursor = cScale;
			case ScaleX:
				int.cursor = cScaleX;
			case ScaleY:
				int.cursor = cScaleY;
			case Rotation:
				int.cursor = cRot;
			}
		};
		int.onPush = function(e:hxd.Event) {
			var z = getZone(e);
			if( z == Pan ) {
				e.cancel = true;
				return;
			}
			if( e.button != 0 )
				return;
			e.propagate = false;
			startMove(z);
		};
		gr = new h2d.Graphics(this);
	}

	public function startMove( t : Transform2D ) {
		var scene = getScene();
		var dragStartX = scene.mouseX;
		var dragStartY = scene.mouseY;
		var dragWidth = int.width, dragHeight = int.height;
		var center = localToGlobal();
		moving = true;
		onStartMove(t);
		int.startDrag(function(e:hxd.Event) {
			switch( e.kind ) {
			case ERelease, EReleaseOutside:
				moving = false;
				int.stopDrag();
				onFinishMove();
			case EMove:
				var dx = scene.mouseX - dragStartX;
				var dy = scene.mouseY - dragStartY;
				inline function scale( m : Float, size : Float ) {
					return Math.max(0, (m + size * 0.5) / (size * 0.5));
				}
				inline function snap(value : Float, step : Float) {
					if (hxd.Key.isDown(hxd.Key.CTRL))
						return Math.round(value / step) * step;
					return value;
				}
				var m = { x : 0., y : 0., scaleX : 1., scaleY : 1., rotation : 0. };
				switch( t ) {
				case Pan:
					m.x = snap(dx, 10);
					m.y = snap(dy, 10);
				case ScaleX:
					m.scaleX = snap(scale(dx * scaleSign, dragWidth), 0.1);
				case ScaleY:
					m.scaleY = snap(scale(dy * scaleSign, dragHeight), 0.1);
				case Scale:
					m.scaleX = m.scaleY = Math.max(snap(scale(dx, dragWidth), 0.1), snap(scale(dy, dragHeight), 0.1));
				case Rotation:
					var startAng =  Math.atan2(dragStartY - center.y, dragStartX - center.x);
					var tmpRotation = hxd.Math.angle(Math.atan2(scene.mouseY - center.y,scene.mouseX - center.x) - startAng);
					m.rotation = snap(tmpRotation, (Math.PI/8));
				default:
				}
				onMove(m);
			default:
			}
		}, function() {
			moving = false;
			onFinishMove();
		});
	}

	function getZone(e:hxd.Event) {
		var px = e.relX + int.x;
		var py = e.relY + int.y;
		var x = (int.width - 16) * 0.5;
		var y = (int.height - 16) * 0.5;
		if( px > x - 2 && py > y - 2 )
			return Scale;
		if( Math.abs(px) > x && Math.abs(py) > y )
			return Rotation;
		if( Math.abs(px) > x ) {
			scaleSign = px > 0 ? 1 : -1;
			return ScaleX;
		}
		if( Math.abs(py) > y ) {
			scaleSign = py > 0 ? 1 : -1;
			return ScaleY;
		}
		return Pan;
	}

	public function setSize(w : Float, h : Float) {
		w = Math.ceil(w/2)*2;
		h = Math.ceil(h/2)*2;
		int.width = w + 10;
		int.height = h + 10;
		int.x = -w*0.5 - 5;
		int.y = -h*0.5 - 5;
		gr.clear();
		gr.lineStyle(1,0xFFFFFF);
		gr.drawRect(-w*0.5-1, -h*0.5-1, w + 2, h + 2);
		gr.lineStyle();
		gr.beginFill(0xFFFFFF);
		gr.drawCircle(-w*0.5-1, -h*0.5-1, 3.5, 32);
		gr.drawCircle(w*0.5+1, -h*0.5-1, 3.5, 32);
		gr.drawCircle(-w*0.5-1, h*0.5+1, 3.5, 32);
		gr.drawRect(w*0.5 - 3, h*0.5 - 3, 7, 7);
		gr.endFill();
	}

}