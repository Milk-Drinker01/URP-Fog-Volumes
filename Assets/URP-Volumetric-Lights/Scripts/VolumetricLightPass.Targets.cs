using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;


public partial class VolumetricLightPass
{
    // Depth render targets
    private static readonly int halfDepthId = Shader.PropertyToID("_HalfDepthTarget");
    private static readonly RenderTargetIdentifier halfDepthTarget = new(halfDepthId);
    private static readonly int quarterDepthId = Shader.PropertyToID("_QuarterDepthTarget");
    private static readonly RenderTargetIdentifier quarterDepthTarget = new(quarterDepthId);



    // Light render targets
    private static readonly int volumeLightId = Shader.PropertyToID("_VolumeLightTexture");
    private static readonly RenderTargetIdentifier volumeLightTexture = new(volumeLightId);
    private static readonly int halfVolumeLightId = Shader.PropertyToID("_HalfVolumeLightTexture");
    private static readonly RenderTargetIdentifier halfVolumeLightTexture = new(halfVolumeLightId);
    private static readonly int quarterVolumeLightId = Shader.PropertyToID("_QuarterVolumeLightTexture");
    private static readonly RenderTargetIdentifier quarterVolumeLightTexture = new(quarterVolumeLightId);


    // Temp render target for temp stuff
    private static readonly int tempId = Shader.PropertyToID("_Temp");
    private RenderTargetIdentifier tempHandle = new(tempId);


    // Active resolution light target
    public RenderTargetIdentifier VolumeLightBuffer 
    {
        get 
        {
            return Resolution switch
            {
                VolumetricResolution.Quarter => quarterVolumeLightTexture,
                VolumetricResolution.Half => halfVolumeLightTexture,
                VolumetricResolution.Full => volumeLightTexture,
                _ => volumeLightTexture,
            };
        }
    }

    public RenderTextureDescriptor lightBufferDescriptor;



    // Get required temporary textures
    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData data)
    {
        RenderTextureDescriptor descriptor = data.cameraData.cameraTargetDescriptor;

        descriptor.depthBufferBits = 0;
        descriptor.colorFormat = RenderTextureFormat.ARGBHalf;

        RenderTextureDescriptor depthDescriptor = descriptor;
        depthDescriptor.colorFormat = RenderTextureFormat.RFloat;


        cmd.GetTemporaryRT(volumeLightId, descriptor, FilterMode.Bilinear);


        if (Resolution == VolumetricResolution.Half)
        {
            descriptor.width /= 2;
            descriptor.height /= 2;
            cmd.GetTemporaryRT(halfVolumeLightId, descriptor, FilterMode.Bilinear);
        }

        // Half/Quarter res both need half-res depth buffer for downsampling
        if (Resolution == VolumetricResolution.Half || Resolution == VolumetricResolution.Quarter) 
        {
            depthDescriptor.width /= 2;
            depthDescriptor.height /= 2;

            cmd.GetTemporaryRT(halfDepthId, depthDescriptor, FilterMode.Point);
        }

        if (Resolution == VolumetricResolution.Quarter)
        {
            descriptor.width /= 4;
            descriptor.height /= 4;

            // Depth descriptor has already been divided previously
            depthDescriptor.width /= 2;
            depthDescriptor.height /= 2;

            cmd.GetTemporaryRT(quarterVolumeLightId, descriptor, FilterMode.Bilinear);
            cmd.GetTemporaryRT(quarterDepthId, depthDescriptor, FilterMode.Point);
        }


        lightBufferDescriptor = descriptor;
    }


    // Release temporary textures
    public override void OnCameraCleanup(CommandBuffer cmd)
    {
        cmd.ReleaseTemporaryRT(volumeLightId);

        if (Resolution == VolumetricResolution.Half)
            cmd.ReleaseTemporaryRT(halfVolumeLightId);

        if (Resolution == VolumetricResolution.Half || Resolution == VolumetricResolution.Quarter)
            cmd.ReleaseTemporaryRT(halfDepthId);

        if (Resolution == VolumetricResolution.Quarter)
        {
            cmd.ReleaseTemporaryRT(quarterVolumeLightId);
            cmd.ReleaseTemporaryRT(quarterDepthId);
        }
    }
}