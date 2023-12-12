package hrt.shgraph;

class Functions extends ShaderNodeHxsl {

    static var SRC = {
        function random (st : Vec2) : Float {
            return fract(sin(dot(st.xy,vec2(12.9898,78.233)))*43758.5453123);
        }
    }
}