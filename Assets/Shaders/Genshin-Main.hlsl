#include "Genshin-Main_inputs.hlsli"


/* Properties */

Texture2D _DiffuseTex;      SamplerState sampler_DiffuseTex;
Texture2D _LightmapTex;     SamplerState sampler_LightmapTex;
Texture2D _NormalTex;       SamplerState sampler_NormalTex;
Texture2D _ShadowRampTex;   SamplerState sampler_ShadowRampTex;
Texture2D _SpecularRampTex; SamplerState sampler_SpecularRampTex;
Texture2D _MetalMapTex;     SamplerState sampler_MetalMapTex;

float _UseShadowRampTex;
float _UseSpecularRampTex;
float _LightArea;
float _ShadowRampWidth;
float _DayOrNight;
float _UseMaterial2;
float _UseMaterial3;
float _UseMaterial4;
float _UseMaterial5;

float _Shininess;
float _Shininess2;
float _Shininess3;
float _Shininess4;
float _Shininess5;
float _SpecMulti;
float _SpecMulti2;
float _SpecMulti3;
float _SpecMulti4;
float _SpecMulti5;
vector<float, 4> _SpecularColor;

float _MTMapBrightness;
float _MTMapTileScale;
float _MTShininess;
float _MTSpecularAttenInShadow;
float _MTSpecularScale;
vector<float, 4> _MTMapDarkColor;
vector<float, 4> _MTMapLightColor;
vector<float, 4> _MTShadowMultiColor;
vector<float, 4> _MTSpecularColor;

/* end of properties */


// vertex
vsOut vert(vsIn v){
    vsOut o;
    o.position = UnityObjectToClipPos(v.vertex);
    o.vertexWS = mul(UNITY_MATRIX_M, vector<float, 4>(v.vertex, 1.0)).xyz; // TransformObjectToWorld
    o.uv.xy = v.uv0;
    o.uv.zw = v.uv1;
    o.normal = v.normal;
    o.vertexcol = v.vertexcol;

    vector<float, 3> worldspaceTangent = UnityObjectToWorldDir(v.tangent.xyz);
    vector<float, 3> worldspaceNormals = UnityObjectToWorldNormal(v.normal);
    vector<float, 3> worldspaceBinormals = cross(worldspaceNormals, worldspaceTangent) * v.tangent.w;

    o.TtoW0 = vector<float, 3>(worldspaceTangent.x, worldspaceBinormals.x, worldspaceNormals.x);
    o.TtoW1 = vector<float, 3>(worldspaceTangent.y, worldspaceBinormals.y, worldspaceNormals.y);
    o.TtoW2 = vector<float, 3>(worldspaceTangent.z, worldspaceBinormals.z, worldspaceNormals.z);

    return o;
}

#include "Genshin-Helpers.hlsl"

// fragment
vector<fixed, 4> frag(vsOut i, bool frontFacing : SV_IsFrontFace) : SV_Target{
    // if frontFacing == 1, use uv.xy, else uv.zw
    vector<half, 2> newUVs = (frontFacing) ? i.uv.xy : i.uv.zw;

    // sample textures to objects
    vector<fixed, 4> lightmap = _LightmapTex.Sample(sampler_LightmapTex, newUVs);
    

    /* NORMAL CREATION */

    vector<fixed, 3> modifiedNormalMap;
    modifiedNormalMap.xy = _NormalTex.Sample(sampler_NormalTex, newUVs).xy * 2 - 1;
    // https://docs.cryengine.com/display/SDKDOC4/Tangent+Space+Normal+Mapping
    modifiedNormalMap.z = sqrt(1 - (modifiedNormalMap.x * modifiedNormalMap.x + modifiedNormalMap.y * 
                          modifiedNormalMap.y));

    // convert to world space
    vector<half, 3> modifiedNormals;
    modifiedNormals.x = dot(i.TtoW0, modifiedNormalMap);
    modifiedNormals.y = dot(i.TtoW1, modifiedNormalMap);
    modifiedNormals.z = dot(i.TtoW2, modifiedNormalMap);

    /* END OF NORMAL CREATION */


    /* DOT CREATION */

    // NdotL
    half NdotL = dot(modifiedNormals, normalize(getlightDir()));
    // remap from { -1, 1 } to { 0, 1 }
    NdotL = NdotL / 2.0 + 0.5;

    // NdotV
    vector<half, 3> viewDir = normalize(_WorldSpaceCameraPos.xyz - i.vertexWS);
    half NdotV = dot(modifiedNormals, viewDir);

    // NdotH
    vector<half, 3> halfVector = normalize(viewDir + _WorldSpaceLightPos0);
    half NdotH = dot(modifiedNormals, halfVector);

    // calculate shadow ramp width from _ShadowRampWidth and i.vertexcol.g
    half ShadowRampWidthCalc = i.vertexcol.g * 2.0 * _ShadowRampWidth;

    // create ambient occlusion from lightmap.g
    half occlusion = lightmap.g * i.vertexcol.r;
    occlusion = smoothstep(0.01, 0.4, occlusion);

    // apply occlusion
    NdotL = lerp(0, NdotL, saturate(occlusion));
    // NdotL_buf will be used as a sharp factor
    half NdotL_buf = NdotL;
    half NdotL_sharpFactor = NdotL_buf < _LightArea;

    // add options for controlling shadow ramp width and shadow push
    NdotL = 1 - ((((_LightArea - NdotL) / _LightArea) / ShadowRampWidthCalc));

    /* END OF DOT CREATION */


    /* MATERIAL IDS */

    half idMasks = lightmap.w;

    half materialID = 1;
    if(idMasks >= 0.2 && idMasks <= 0.4 && _UseMaterial4 != 0){
        materialID = 4;
    } 
    else if(idMasks >= 0.4 && idMasks <= 0.6 && _UseMaterial3 != 0){
        materialID = 3;
    }
    else if(idMasks >= 0.6 && idMasks <= 0.8 && _UseMaterial5 != 0){
        materialID = 5;
    }
    else if(idMasks >= 0.8 && idMasks <= 1.0 && _UseMaterial2 != 0){
        materialID = 2;
    }

    /* END OF MATERIAL IDS */


    /* SHADOW RAMP CREATION */

    vector<half, 2> ShadowRampDayUVs = vector<float, 2>(NdotL, (((6 - materialID) - 1) * 0.1) + 0.05);
    vector<fixed, 4> ShadowRampDay = _ShadowRampTex.Sample(sampler_ShadowRampTex, ShadowRampDayUVs);

    vector<half, 2> ShadowRampNightUVs = vector<float, 2>(NdotL, (((6 - materialID) - 1) * 0.1) + 0.05 + 0.5);
    vector<fixed, 4> ShadowRampNight = _ShadowRampTex.Sample(sampler_ShadowRampTex, ShadowRampNightUVs);

    vector<fixed, 4> ShadowRampFinal = lerp(ShadowRampNight, ShadowRampDay, _DayOrNight);

    // switch between 1 and ramp edge like how the game does it, also make eyes always lit
    ShadowRampFinal = (NdotL_sharpFactor && lightmap.g < 0.85) ? ShadowRampFinal : 1;

    /* END OF SHADOW RAMP CREATION */


    /* METALLIC */

    // multiply world space normals with view matrix
    vector<half, 3> viewNormal = mul(UNITY_MATRIX_V, modifiedNormals);
    // https://github.com/poiyomi/PoiyomiToonShader/blob/master/_PoiyomiShaders/Shaders/8.0/Poiyomi.shader#L8397
    // this part (all 5 lines) i literally do not understand but it fixes the skewing that occurs when the camera 
    // views the mesh at the edge of the screen (PLEASE LET ME GO BACK TO BLENDER)
    vector<half, 3> matcapUV_Detail = viewNormal.xyz * vector<half, 3>(-1, -1, 1);
    vector<half, 3> matcapUV_Base = (mul(UNITY_MATRIX_V, vector<half, 4>(viewDir, 0)).rgb 
                                    * vector<half, 3>(-1, -1, 1)) + vector<half, 3>(0, 0, 1);
    vector<half, 3> matcapUVs = matcapUV_Base * dot(matcapUV_Base, matcapUV_Detail) 
                                / matcapUV_Base.z - matcapUV_Detail;

    // offset UVs to middle and apply _MTMapTileScale
    matcapUVs = vector<half, 3>(matcapUVs.x * _MTMapTileScale, matcapUVs.y, 0) * 0.5 + vector<half, 3>(0.5, 0.5, 0);

    // sample matcap texture with newly created UVs
    vector<fixed, 4> metal = _MetalMapTex.Sample(sampler_MetalMapTex, matcapUVs);
    metal *= _MTMapBrightness;
    metal = lerp(_MTMapDarkColor, _MTMapLightColor, metal);

    // apply _MTShadowMultiColor ONLY to shaded areas
    metal = (NdotL_sharpFactor) ? metal * _MTShadowMultiColor : metal;

    /* END OF METALLIC */


    /* METALLIC SPECULAR */
    
    vector<half, 4> metalSpecular = NdotH;
    metalSpecular = pow(metalSpecular, _MTShininess) * _MTSpecularScale;

    // if _UseSpecularRampTex is set to 1, shrimply use the specular ramp texture
    if(_UseSpecularRampTex != 0){
        metalSpecular = _SpecularRampTex.Sample(sampler_SpecularRampTex, vector<half, 2>(metalSpecular.x, 0.5));
    }
    else{
        metalSpecular *= lightmap.b;
    }

    // apply _MTSpecularColor
    metalSpecular *= _MTSpecularColor;
    // apply _MTSpecularAttenInShadow ONLY to shaded areas
    metalSpecular = saturate((NdotL_sharpFactor) ? metalSpecular * _MTSpecularAttenInShadow : metalSpecular);

    /* END OF METALLIC SPECULAR */


    /* SPECULAR */

    // combine all the _Shininess parameters into one object
    half globalShininess = _Shininess;
    if(materialID == 2){
        globalShininess = _Shininess2;
    }
    else if(materialID == 3){
        globalShininess = _Shininess3;
    }
    else if(materialID == 4){
        globalShininess = _Shininess4;
    }
    else if(materialID == 5){
        globalShininess = _Shininess5;
    }

    // combine all the _SpecMulti parameters into one object
    half globalSpecMulti = _SpecMulti;
    if(materialID == 2){
        globalSpecMulti = _SpecMulti2;
    }
    else if(materialID == 3){
        globalSpecMulti = _SpecMulti3;
    }
    else if(materialID == 4){
        globalSpecMulti = _SpecMulti4;
    }
    else if(materialID == 5){
        globalSpecMulti = _SpecMulti5;
    }

    vector<half, 4> specular = NdotH;
    // apply _Shininess parameters
    specular = pow(specular, globalShininess);
    // 1.03 may seem arbitrary, but it is shrimply an optimization due to Unity compression, it's supposed to be a 
    // inversion of lightmap.b, also compare specular to inverted lightmap.b
    specular = (1.03 - lightmap.b) < specular;
    specular = saturate(specular * globalSpecMulti * _SpecularColor * lightmap.r * _SpecularColor);

    /* END OF SPECULAR */

    
    /* COLOR CREATION */

    // apply diffuse ramp
    vector<fixed, 4> finalColor = vector<fixed, 4>(_DiffuseTex.Sample(sampler_DiffuseTex, newUVs).xyz, 1) * 
                                  ShadowRampFinal;

    // apply metallic only to anything above 0.9 of lightmap.r
    finalColor = (lightmap.r > 0.9) ? finalColor * metal : finalColor;

    // add specular to finalColor if lightmap.r is less than 0.9, else add metallic specular
    finalColor = (lightmap.r > 0.9) ? finalColor + metalSpecular : finalColor + specular;

    return finalColor;

    /* END OF COLOR CREATION */
}