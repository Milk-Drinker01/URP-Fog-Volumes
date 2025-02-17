#pragma once

#if defined(PROBE_VOLUMES_L1) || defined(PROBE_VOLUMES_L2)
#include "Packages/com.unity.render-pipelines.core/Runtime/Lighting/ProbeVolume/ProbeVolume.hlsl"
#endif

struct Attributes
{
	float4 vertex : POSITION;
	float2 uv : TEXCOORD0;
};


struct Varyings
{
	float4 vertex : SV_POSITION;
	float3 viewPosition : TEXCOORD0;
	float2 uv : TEXCOORD1;
};


#if defined(NOISE_ENABLED)
	TEXTURE3D(_NoiseTexture);
	SAMPLER(sampler_NoiseTexture);
	float4 _NoiseData; // x: scale, y: intensity, z: intensity offset
	float3 _NoiseVelocity; // noise move direction
#endif

TEXTURE2D(_CameraDepthTexture);
SAMPLER(sampler_CameraDepthTexture);

half3 _Albedo;
float _IntensityModifier;

int _SampleCount; 
float4 _StepParams; // x: minimum, y: maximum, z: increment factor, w: max ray length
float _Jitter;

float _Scattering;
float _Extinction;
float _MieG;

float _BrightnessClamp;

float4 _ViewportRect;
float _MaxRayLength;
float2 _FogRange;

float3 _EdgeFade;

float3x4 _InvMatrix;


float FadeBoxEdge(float3 worldPosition)
{
	float3 localPos = mul(_InvMatrix, float4(worldPosition, 1.0)).xyz;

	float edgeX = smoothstep(_EdgeFade.x, 0.5, min(localPos.x + 0.5, 0.5 - localPos.x));
	float edgeY = smoothstep(_EdgeFade.y, 0.5, min(localPos.y + 0.5, 0.5 - localPos.y));
    float edgeZ = smoothstep(_EdgeFade.z, 0.5, min(localPos.z + 0.5, 0.5 - localPos.z));

	return min(min(edgeX, edgeY), edgeZ);
}


float FadeSphereEdge(float3 worldPosition)
{
	float3 localPos = mul(_InvMatrix, float4(worldPosition, 1.0)).xyz;
	float dist = 0.5 - length(localPos);

	return smoothstep(_EdgeFade.x, 0.5, dist);
}


float FadeCylinderEdge(float3 worldPosition)
{
	float3 localPos = mul(_InvMatrix, float4(worldPosition, 1.0)).xyz;

	float dist = 0.5 - length(localPos.xz);

	float sphereRad = smoothstep(_EdgeFade.x, 0.5, dist);
	float yEdge = smoothstep(_EdgeFade.y, 1, min(localPos.y + 1, 1 - localPos.y));

	return min(sphereRad, yEdge);
}


float FadeCapsuleEdge(float3 worldPosition)
{	
	float3 localPos = mul(_InvMatrix, float4(worldPosition, 1.0)).xyz;

	const float3 ab = float3(0, 1, 0);
	float3 ac = localPos - float3(0, -0.5, 0);
	float3 bc = localPos - float3(0, 0.5, 0);

    float e = dot(ac, ab);

	float dist;

    // Handle cases where c projects outside ab
    if (e <= 0.0f) 
		dist = sqrlen(ac);
	else
	{
		float f = sqrlen(ab);
		dist = e >= f ? sqrlen(bc) : sqrlen(ac) - e * e / f;
	}

	return smoothstep(_EdgeFade.x, 0.5, (0.5 - sqrt(dist)));
}



float GetDensity(float3 worldPosition, float distance)
{
    float density = 1.0;

	#if defined(NOISE_ENABLED)
		// Scale sample position
		float3 samplePos = (worldPosition * _NoiseData.x);
		
		// Offset sample position
		samplePos += _Time.y * _NoiseVelocity;

		float noise = SAMPLE_BASE3D(_NoiseTexture, sampler_NoiseTexture, samplePos).x;
		density = saturate(noise - _NoiseData.z) * _NoiseData.y;
	#endif

	#if defined(CUBE_VOLUME)
		density *= FadeBoxEdge(worldPosition);
	#elif defined(CAPSULE_VOLUME)
		density *= FadeCapsuleEdge(worldPosition);
	#elif defined(CYLINDER_VOLUME)
		density *= FadeCylinderEdge(worldPosition);
	#else
		density *= FadeSphereEdge(worldPosition);
	#endif
    
	// Fade density as position gets further from camera
    return density * smoothstep(_FogRange.x, _FogRange.y, distance);
}        


// Original from https://github.com/SlightlyMad/VolumetricLights/blob/master/Assets/Shaders/VolumetricLight.shader under the BSD license
float MiePhase(float cosAngle, float mieG)
{
	float gSqr = sqr(mieG);

	// Magic number is 1/4pi
    return (0.07957747154) * ((1 - gSqr) / (pow(abs((1 + gSqr) - (2 * mieG) * cosAngle), 1.5)));
}


half3 GetLightAttenuationMie(float3 worldPosition, float3 direction, float mieG)
{
    half3 totalColor = 0.0;

    #if defined(LIGHTING_ENABLED) || defined(SHADOWS_ENABLED)
        for (int i = 0; i < min(_LightCount, MAX_LIGHT_COUNT); i++)
        {
            float3 lightDir;
            half3 lightColor = GetLightAttenuation(worldPosition, i, lightDir);

            lightColor *= MiePhase(dot(lightDir, direction), mieG);  

            totalColor += lightColor;
        }
    #endif

	return totalColor;
}


half3 RayMarch(float3 rayStart, float3 rayDir, float rayLength, float3 cameraPos, float2 ScreenPos)
{
	float cameraDistance = length(cameraPos - rayStart);

	float extinction = cameraDistance * _Extinction * 0.5; // Assume density of 0.5 between camera and fog volume

	float stepSize = _StepParams.x;

	half3 vlight = 0;
	float distance = 0;

	[loop]
	for (int i = 0; i < _SampleCount; ++i)
	{
		if (distance >= rayLength)
			break;

		float3 currentPosition = rayStart + rayDir * distance;

		half3 light = _Albedo;
		light += GetLightAttenuationMie(currentPosition, rayDir, _MieG) * _IntensityModifier;
		
		float density = GetDensity(currentPosition, distance + cameraDistance);

        float scattering = _Scattering * stepSize * density;
		extinction += _Extinction * stepSize * density;

		light *= scattering * exp(-extinction);
		
#if defined(PROBE_VOLUMES_L1) || defined(PROBE_VOLUMES_L2)
        float3 apvDiffuseGI;
        EvaluateAdaptiveProbeVolume(currentPosition, ScreenPos, apvDiffuseGI);
        
        if (AnyIsNaN(apvDiffuseGI))
        {
            apvDiffuseGI = float3(0, 0, 0);
        }
        light += apvDiffuseGI / 300;
#endif

		vlight += light;
		distance += stepSize;	

		stepSize = min(_StepParams.y, stepSize * _StepParams.z);			
	}

	vlight = clamp(vlight, 0, _BrightnessClamp);

	return vlight;
}



half3 CalculateVolumetricLight(float3 cameraPos, float3 viewDir, float linearDepth, float2 uv)
{
	bool hit = false;
    float near = 0;
    float far = _FogRange.x;

	#if defined(CUBE_VOLUME)
		hit = RayCube(_InvMatrix, cameraPos, viewDir, near, far);
	#elif defined(CAPSULE_VOLUME)
		hit = RayCapsule(_InvMatrix, cameraPos, viewDir, near, far);
	#elif defined(CYLINDER_VOLUME)
		hit = RayCylinder(_InvMatrix, cameraPos, viewDir, near, far);
	#else
		// Default to sphere
		hit = RaySphere(_InvMatrix, cameraPos, viewDir, near, far);
	#endif

	// No intersection
    if (!hit)
        return 0;	
    
    far = min(far, linearDepth);
    float rayLength = (far - near);

    // Object is behind scene depth
    if (rayLength < 0)
        return 0;

    // Jump to point on intersection surface, then add jitter
    float3 rayStart = cameraPos + viewDir * (near + MathRand(uv) * _Jitter);

    return RayMarch(rayStart, viewDir, min(rayLength, _StepParams.w), cameraPos, uv);
}



Varyings VolumetricVertex(Attributes v)
{
	Varyings output = (Varyings)0;
	output.vertex = CorrectVertex(v.vertex);

	float2 vertex01 = output.vertex.xy * 0.5 + 0.5;

	// Clamp UV-space vertex to viewport
	vertex01 = min(max(vertex01, _ViewportRect.xy), _ViewportRect.xy + _ViewportRect.zw);
	output.uv = vertex01;

	output.vertex.xy = vertex01 * 2 - 1;

	output.vertex = CorrectVertex(output.vertex);

	return output;
}


half3 VolumetricFragment(Varyings i) : SV_Target
{
	float2 uv = i.uv;

	#if defined(TEMPORAL_RENDERING_ENABLED)
		uv = FullUVFromLowResUV(uv);
	#endif

	// Get view vector using UV
	float3 viewVector = mul(unity_CameraInvProjection, float4(uv * 2 - 1, 0, -1)).xyz;
	viewVector = mul(unity_CameraToWorld, float4(viewVector, 0)).xyz;

	float len = length(viewVector);
	float3 rayDir = viewVector / len;				

	float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, uv);
	float linearDepth = LINEAR_EYE_DEPTH(depth) * len;

	half3 light = CalculateVolumetricLight(_WorldSpaceCameraPos.xyz, rayDir, linearDepth, uv);

	return light;
}


