package hrt.tools;

/**
    Static extension for h3d.scene.Graphics
**/
class GraphicsTools {
    static public function drawPointCross(g: h3d.scene.Graphics, x: Float, y: Float, z: Float, width: Float) {
        g.moveTo(x-width, y, z);
        g.lineTo(x+width, y, z);
        g.moveTo(x, y-width, z);
        g.lineTo(x,y+width, z);
        g.moveTo(x,y,z-width);
        g.lineTo(x,y,z+width);
    }
}