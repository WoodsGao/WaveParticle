Shader "Instanced/InstancedShader" {
    Properties {
        _Scale ("Scale", Float) = 1
    }
    SubShader {

        Pass {

            Tags {"LightMode"="ForwardBase"}
            Blend One One
            Cull Off
            CGPROGRAM

            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdbase nolightmap nodirlightmap nodynlightmap novertexlight
            #pragma target 4.5

            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"
            #include "AutoLight.cginc"

            sampler2D _MainTex;
            float4 _WorldToClip;
            float _Scale;

            #if SHADER_TARGET >= 45
                StructuredBuffer<uint> _AlivePool;
                StructuredBuffer<float4> _PositionBuffer;
            #endif

            struct v2f
            {
                float4 pos : SV_POSITION;
                float4 uv : TEXCOORD0;
            };
            
            float2 GetClipPosFromWorld(float2 worldXZ)
            {
                float2 pos = worldXZ * _WorldToClip.xy + _WorldToClip.zw;
                pos.y = -pos.y;
                return pos;
            }

            v2f vert (appdata_full v, uint instanceID : SV_InstanceID)
            {
                #if SHADER_TARGET >= 45
                    uint realID = _AlivePool[instanceID];
                    float4 position = _PositionBuffer[realID];
                #else
                    float4 position = 0;
                #endif

                float2 clipPos = GetClipPosFromWorld(position.xy + _Scale*v.vertex.xy);

                v2f o;
                // o.pos = mul(UNITY_MATRIX_VP, float4(worldPosition, 1.0f));
                o.pos = float4(clipPos, 0,1);
                o.uv = float4(v.vertex.xy, position.z, 0);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float distance = pow(saturate(1-length(i.uv.xy)), 5) * i.uv.z;
                float2 worldNormalXZ = i.uv.xy * distance;
                return float4(worldNormalXZ,-worldNormalXZ);
            }

            ENDCG
        }
    }
}