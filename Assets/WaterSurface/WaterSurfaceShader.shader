Shader "Water/WaterSurfaceShader"
{
    Properties
    {
        _FoamTex ("Foam", 2D) = "white" {}
        _CausticTex ("Caustic", 2D) = "white" {}
        _DerivHeight ("Texture", 2D) = "white" {}
        _FlowMap ("Flow (RG, A noise)", 2D) = "black" {}
        _WaveHeight ("Wave Particle Height", 2D) = "black" {}
        _Tiling ("Tiling", Float) = 1
        _FlowOffset ("Flow Offset", Float) = 0
        _UJump ("U jump per phase", Range(-0.25, 0.25)) = 0.25
        _VJump ("V jump per phase", Range(-0.25, 0.25)) = 0.25

        _WaterRange ("Water Range", Float) = 1
        _ShadowIntensity ("Shadow Intensity", Float) = 1
        _WaveIntensity ("Wave Intensity", Float) = 1
        _NormalIntensity ("Normal Intensity", Range(0, 1)) = 1
        _DecayFactor ("Decay Factor(Near, Far, Horizontal, SkyBoxLOD)", Vector) = (0,0,0,0)
        _Metallic ("Metallic", Range(0, 1)) = 1
        _SSSFactor ("SSS Factor", Vector) = (0,0,0,0)
        _SSRFactor ("SSR Factor", Vector) = (0,0,0,0)
        _FoamFactor ("Foam Factor", Vector) = (0,0,0,0)

        _AlbedoColor ("Diffuse Color", Color) = (0,0,0,0)
        _RefractFog ("Refract Fog", Color) = (0,0,0,0)
        _Fog ("Real Fog", Color) = (0,0,0,0)
    }
    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent"}
        LOD 100

        GrabPass
        {
            "_CameraOpaqueTexture"
        }

        Pass
        {
            Cull Back

            Blend SrcAlpha OneMinusSrcAlpha 
            ZWrite Off
            // ZTest Off
            CGPROGRAM
            #pragma multi_compile_fog
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "AutoLight.cginc"
            #include "Shadow.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float4 worldPos : TEXCOORD0;
                float4 screenPos : TEXCOORD1;
                SHADOW_COORDS(3)
            };

            // sampler2D _SunCascadedShadowMap;
            sampler2D _CameraDepthTexture, _CameraOpaqueTexture, _DepthCast, _WaveHeight, _FoamTex, _CausticTex;
            float4 _DepthCast_ST, _WaveHeight_ST, _FoamTex_ST, _CausticTex_ST;

            sampler2D _DerivHeight;
            float4 _DerivHeight_ST;
            sampler2D _FlowMap;
            float4 _FlowMap_ST;
            float _FlowOffset, _Tiling, _UJump, _VJump, _WaterRange, _NormalIntensity,
            _Metallic, _ShadowIntensity, _WaveIntensity;
            float4 _AlbedoColor, _RefractFog, _Fog, _DecayFactor, _SSSFactor, _SSRFactor, _FoamFactor;

            float3 FlowUVW (
            float2 uv, float2 flowVector, float2 jump,
            float flowOffset, float tiling, float time, bool flowB
            ) {
                float phaseOffset = flowB ? 0.5 : 0;
                float progress = frac(time + phaseOffset);
                float3 uvw;
                uvw.xy = uv - flowVector * (progress + flowOffset);
                uvw.xy *= tiling;
                uvw.xy += phaseOffset;
                uvw.xy += (time - progress) * jump;
                uvw.z = 1 - abs(1 - 2 * progress);
                return uvw;
            }

            float3 UnpackDerivativeHeight (float4 textureData) {
                float3 dh = textureData.agb;
                dh.xy = dh.xy * 2 - 1;
                return dh;
            }

            float4 CalFlowDerivHeight(float2 uv, float tiling) {

                float4 flow= tex2Dlod(_FlowMap, float4(TRANSFORM_TEX(uv, _FlowMap) * 0.01, 0, 0));
                float noise = flow.a;
                float2 flowVector = flow.xy * 2.0 - 1.0;
                float time = _Time.y + noise;
                float2 jump = float2(_UJump, _VJump);

                float3 uvwA = FlowUVW(
                uv, flowVector, jump,
                _FlowOffset, tiling, time, false
                );
                float3 uvwB = FlowUVW(
                uv, flowVector, jump,
                _FlowOffset, tiling, time, true
                );

                float3 dhA = UnpackDerivativeHeight(tex2Dlod(_DerivHeight, float4(uvwA.xy, 0, 0))) * uvwA.z;
                float3 dhB = UnpackDerivativeHeight(tex2Dlod(_DerivHeight, float4(uvwB.xy, 0, 0))) * uvwB.z;
                return float4(dhA + dhB, noise);
            }

            inline float4 ClipToWorld(float4 vertex) {
                return mul(unity_CameraToWorld, mul(unity_CameraInvProjection, vertex));
            }

            float3 GetWorldPosFromDepth(float2 screenPos) {
                // Sample the depth texture to get the linear 01 depth
                float depth = UNITY_SAMPLE_DEPTH(tex2Dlod(_CameraDepthTexture, float4(screenPos, 0.0, 0.0)));
                depth = Linear01Depth(depth);
                // NDC position
                // View space vector pointing to the far plane
                float far = _ProjectionParams.z;
                float3 clipVec = float3(screenPos * 2 - 1, 1.0) * far;
                float3 viewVec = mul(unity_CameraInvProjection, clipVec.xyzz).xyz;
                float3 viewPos = viewVec * depth;
                float3 worldPos = mul(UNITY_MATRIX_I_V, float4(viewPos, 1.0)).xyz;
                return worldPos;
            }

            bool RayMarching(float3 worldPos, float3 reflectDir,inout float2 uv)
            {
                float rayLength = 0;
                float stepSize = _SSRFactor.x;
                float thickness = _SSRFactor.y;


                float4 screenPos = mul(UNITY_MATRIX_VP, float4(worldPos, 1));
                screenPos /= screenPos.w;
                float4 screenPosEnd = mul(UNITY_MATRIX_VP, float4(worldPos + reflectDir, 1));
                screenPosEnd /= screenPosEnd.w;
                float startToEnd = length(screenPosEnd.xy - screenPos.xy);
                // if (startToEnd < 0.0001) return false;
                reflectDir /= max(startToEnd * 0.5, 0.03);
                for (float i = 0; i < _SSRFactor.z; i++)
                {
                    rayLength += stepSize;
                    float4 pos = float4(worldPos + rayLength * reflectDir, 1);
                    float4 viewPos = mul(UNITY_MATRIX_V, pos);
                    float4 clipPos = mul(UNITY_MATRIX_P, viewPos);
                    uv = clipPos.xy / clipPos.w * 0.5 + 0.5;
                    uv.y = 1 - uv.y;
                    float depth = UNITY_SAMPLE_DEPTH(tex2Dlod(_CameraDepthTexture, float4(uv, 0.0, 0.0)));
                    depth = LinearEyeDepth(depth);
                    // collied if ray hit point is back of screen opaque point 
                    float collied = depth + viewPos.z;
                    bool inScreen = uv.x > 0 && uv.x < 1 && uv.y > 0 && uv.y < 1;
                    if (inScreen && collied < 0 && -collied < thickness) 
                    {
                        // uv.x = i / 30;
                        return true;
                    }
                    if (!inScreen || (collied < 0 && -collied > thickness))
                    {
                        rayLength -= stepSize;
                        stepSize *= 0.5;
                        stepSize = max(_SSRFactor.w, stepSize);
                    }
                }
                // uv.x = 1;
                return false;
            }

            float GetHeightWeight(float3 worldPos)
            {
                float waterLevel = unity_ObjectToWorld[1][3];

                float4 encodedHeight = tex2Dlod(_DepthCast, float4(TRANSFORM_TEX(worldPos.xz,_DepthCast), 0, 0));
                float h = (DecodeFloatRGBA(encodedHeight)-0.5)*1000;
                float verticleHeight = h - waterLevel;

                float distance = length(worldPos.xyz - _WorldSpaceCameraPos.xyz);
                
                float nearWeight = saturate(1-exp(verticleHeight*_DecayFactor.x));
                float farWeight = saturate(exp(-distance*_DecayFactor.y*0.01));
                float horizonWeight = pow(abs(dot(normalize(worldPos.xyz - _WorldSpaceCameraPos.xyz), float3(0,1,0))), _DecayFactor.z);

                return nearWeight * farWeight * horizonWeight;
            }

            v2f vert (appdata v)
            {
                float waterLevel = unity_ObjectToWorld[1][3];
                float4 vertex = v.vertex;
                vertex.xyz *= 1+_WaterRange;

                v2f o;

                float4 worldPos = ClipToWorld(float4(vertex.xyz, 1.0));
                worldPos = worldPos / worldPos.w;
                float3 viewDir = worldPos.xyz - _WorldSpaceCameraPos;
                viewDir.y = max(viewDir.y, 0.001);
                float rayLength = (waterLevel - _WorldSpaceCameraPos.y ) / viewDir.y;
                float3 projectedWorldPos = _WorldSpaceCameraPos + rayLength * viewDir;

                o.worldPos = float4(projectedWorldPos, 1.0);
                o.worldPos.y += CalFlowDerivHeight(o.worldPos.xz, _Tiling*0.01).z * _WaterRange * GetHeightWeight(o.worldPos.xyz);
                o.pos = mul(UNITY_MATRIX_VP, o.worldPos);

                o.screenPos = ComputeScreenPos(o.pos);

                TRANSFER_SHADOW(o);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float3 screenPos = i.screenPos.xyz/i.screenPos.w;

                float waterLevel = unity_ObjectToWorld[1][3];


                float2 waveUV = TRANSFORM_TEX(i.worldPos.xz,_WaveHeight);
                float4 waveHeight = float4(0,0,0,0);
                if (waveUV.x>0 && waveUV.x<1 && waveUV.y>0 && waveUV.y<1)
                {
                    waveHeight = tex2D(_WaveHeight, waveUV);
                }
                float2 waveNormalXZ = waveHeight.xy - waveHeight.zw;
                float3 waveNormal = float3(waveNormalXZ.x, 0, waveNormalXZ.y);

                float4 encodedHeight = tex2D(_DepthCast, TRANSFORM_TEX(i.worldPos.xz,_DepthCast));
                float h = (DecodeFloatRGBA(encodedHeight)-0.5)*1000;
                float verticleHeight = h - waterLevel;

                float distance = length(i.worldPos.xyz - _WorldSpaceCameraPos.xyz);

                float4 dh = CalFlowDerivHeight(i.worldPos.xz, _Tiling*0.01);
                float3 normal = normalize(float3(-dh.x, 0.2, -dh.y) + waveNormal * _WaveIntensity );
                normal = lerp(float3(0, 1, 0), normal, _NormalIntensity * GetHeightWeight(i.worldPos));

                float3 worldPos = float3(i.worldPos.x, waterLevel + dh.z * _WaterRange * (1-exp(verticleHeight*0.3)), i.worldPos.z);
                verticleHeight = h - worldPos.y;
                float3 viewDir = normalize(UnityWorldSpaceViewDir(worldPos));
                float3 lightDir = normalize(UnityWorldSpaceLightDir(worldPos));


                // SSR
                float3 reflectDir = reflect(-viewDir, normal);
                float3 reflectColor = float3(0,0,0);
                float2 hitUV = float2(0,0);
                float4 hdrColor = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, float4(reflectDir, 0), saturate(exp(-distance*_DecayFactor.w)));
                reflectColor = DecodeHDR(hdrColor, unity_SpecCube0_HDR);if (distance < 50 && RayMarching(worldPos, reflectDir, hitUV))
                {
                    reflectColor *= 0.3;
                    reflectColor += tex2D(_CameraOpaqueTexture, hitUV).rgb * 0.7;
                }
                // reflectColor = lerp(reflectColor, _LightColor0 * saturate(dot(lightDir, reflectDir)), 0);
                // reflectColor *= 0.85;
                // return float4(reflectColor,1);

                // refract in water
                float3 terrianHit = GetWorldPosFromDepth(screenPos.xy);
                float distanceInWater = length(terrianHit - _WorldSpaceCameraPos.xyz);
                
                float2 distortedUV = screenPos.xy + normal.xz * 0.1 * (1-exp(-distanceInWater));
                float distortedDepth = UNITY_SAMPLE_DEPTH(tex2Dlod(_CameraDepthTexture, float4(distortedUV, 0.0, 0.0)));
                distortedDepth = LinearEyeDepth(distortedDepth);
                if (distortedDepth <= distance + 0.1)
                {
                    distortedUV = screenPos.xy;
                }
                else
                {
                    distanceInWater = distortedDepth;
                }
                // return float4(distanceInWater*0.1,0,0,1);
                distanceInWater -= distance;
                // distanceInWater = min(distanceInWater, 10*distance);
                distanceInWater = min(distanceInWater, abs(50/ viewDir.y));

                float density_water = 1 / 1 - pow(_RefractFog.a , 0.1f) + 0.00001f;
                float f_water = 1 - exp(-pow(density_water * distanceInWater, 1));
                float3 refractColor = tex2D(_CameraOpaqueTexture, distortedUV);
                // caustic
                float3 caustic = tex2D(_CausticTex, TRANSFORM_TEX((terrianHit.xz + normal.xz*5),_CausticTex));
                caustic = caustic * exp(-distanceInWater * 0.5) * 0.35;
                // return float4(caustic, 1);

                refractColor = _RefractFog.rgb * f_water + (refractColor + caustic) * (1 - f_water);
                // return float4(refractColor,1);

                // fresnel
                float fresnel = saturate(_Metallic + (1- _Metallic) * pow(1 - dot(normal, viewDir), 5)) * 0.8;
                float3 color = fresnel * reflectColor + (1 - fresnel) * refractColor;


                // fast SSS
                float intensitySSS = saturate(dot(viewDir, -normalize(lightDir + _SSSFactor.x * normal)));
                intensitySSS = pow(intensitySSS, _SSSFactor.y) * _SSSFactor.z;
                color += intensitySSS * _RefractFog.rgb;


                // foam
                float foamWeight = saturate(exp(verticleHeight * _FoamFactor.x)) * _FoamFactor.y;
                float foamColor = tex2D(_FoamTex, TRANSFORM_TEX((worldPos.xz + dh.xy * 0.1 + sin(_Time) * 0.1), _FoamTex)).r;
                
                foamWeight = max(foamWeight, saturate((lerp(length(waveNormalXZ),+dh.z, _FoamFactor.w) - _FoamFactor.z) / _FoamFactor.w));
                float foam = step(1-foamWeight, foamColor);
                // return float4(foamWeight,0,0,1);

                color = lerp(color, float3(1,1,1)*0.95, foam);
                // return float4(foam,0,0,1);

                // shadow
                float shadow = distance < 100 ? max((1-_ShadowIntensity), GetSunShadowsAttenuation_PCF5x5(worldPos, screenPos.z, 0).x) : 1;
                color *= shadow;


                // refract fog
                float f_fog = 1 - exp(-pow(_Fog.a * distance * 0.1, 1));
                color = f_fog * _Fog.rgb + (1 - f_fog) * color;

                return float4(color,1);
            }
            ENDCG
        }
    }
}
