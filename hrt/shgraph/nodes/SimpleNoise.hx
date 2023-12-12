package hrt.shgraph.nodes;


// Disabled at the moment
//@name("Simple Noise")
//@description("The output is the sinus of A")
//@width(120)
//@group("Generation")
class SimpleNoise extends ShaderNodeHxsl {

	static var SRC = {
		@sginput(calculatedUV) var uv : Vec2;
        @sginput(1.0) var scale : Vec2;
		@sgoutput var output : Float;

        @:import hrt.shgraph.Functions;

		/*function fragment() {
            var uv2 = uv * scale;
            var iUv = floor(uv2);
            var fUv = uv2 - iUv;
            var s0 = fract(sin(dot(iUv+vec2(0.0,0.0),vec2(12.9898,78.233)))*43758.5453123);
            var s1 = fract(sin(dot(iUv+vec2(1.0,0.0),vec2(12.9898,78.233)))*43758.5453123);
            var s2 = fract(sin(dot(iUv+vec2(0.0,1.0),vec2(12.9898,78.233)))*43758.5453123);
            var s3 = fract(sin(dot(iUv+vec2(1.0,1.0),vec2(12.9898,78.233)))*43758.5453123);

            var m0 = mix(s0, s1, smoothstep(0.0,1.0,fUv.x));
            var m1 = mix(s2, s3, smoothstep(0.0,1.0,fUv.x));

            output = mix(m0, m1, smoothstep(0.0,1.0,fUv.y));            
		}*/


        function grad(z : Vec2 ) : Vec2  // replace this anything that returns a random vector
        {
            // 2D to 1D  (feel free to replace by some other)
            var n : Int = int(z.x+z.y*11111);

            // Hugo Elias hash (feel free to replace by another one)
            n = (n<<13)^n;
            n = (n*(n*n*15731+789221)+1376312589)>>16;

            // Perlin style vectors
            n &= 7;
            var gr = vec2(n&1,n>>1)*2.0-1.0;
            return ( n>=6 ) ? vec2(0.0,gr.x) : 
                ( n>=4 ) ? vec2(gr.x,0.0) :
                                    gr;                         
        }

        function fragment()
        {
            var p = uv;
            var i = vec2(floor( p ));
            var f =       fract( p );
            
            var u = f*f*(3.0-2.0*f); // feel free to replace by a quintic smoothstep instead

            output = mix( mix( dot( grad( i+vec2(0,0) ), f-vec2(0.0,0.0) ), 
                            dot( grad( i+vec2(1,0) ), f-vec2(1.0,0.0) ), u.x),
                        mix( dot( grad( i+vec2(0,1) ), f-vec2(0.0,1.0) ), 
                            dot( grad( i+vec2(1,1) ), f-vec2(1.0,1.0) ), u.x), u.y);
        }
	};

}