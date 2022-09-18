Shader "Water/DepthCaster"
{
    Properties
    {
    }
    SubShader
    {
        Tags {"RenderType"="Opaque"}
        ZTest On
        Cull Off
        ZWrite On

        LOD 200
        Pass
        {
            CGPROGRAM

            #pragma target 4.5
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            struct appdata {
                float4 vertex:POSITION;
            };

            struct v2f {
                float4 pos:SV_POSITION;
                float4 worldPos:TEXCOORD0;
            };


            v2f vert(appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex.xyz);
                o.worldPos = mul(UNITY_MATRIX_M, float4(v.vertex.xyz, 1.0));
                return o;
            }
            fixed4 frag(v2f i) :SV_Target
            {
                return float4(EncodeFloatRGBA(saturate(i.worldPos.y*0.001+0.5)));
            }
            ENDCG
        }

    }
}