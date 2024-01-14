using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;


#if UNITY_EDITOR
using UnityEditor;
using UnityEngine.SceneManagement;
using UnityEditor.SceneManagement;
#endif


public class VolumetricFogFeature : ScriptableRendererFeature
{
    public VolumetricResolution resolution;
    
    private VolumetricFogPass lightPass;
    private Shader bilateralBlur;
    private Shader volumetricFog;


    public override void Create()
    {
        ValidateShaders();

        lightPass = new VolumetricFogPass(this, bilateralBlur, volumetricFog) 
        { 
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing,
        };

#if UNITY_EDITOR
        EditorSceneManager.activeSceneChangedInEditMode += OnSceneChanged;
#endif
    }

#if UNITY_EDITOR
    // For some reason light pass must be refreshed on editor scene changes or else output color will be completely black
    private void OnSceneChanged(Scene a, Scene b)
    { 
        lightPass = new VolumetricFogPass(this, bilateralBlur, volumetricFog) 
        { 
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing,
        };
    }

    protected override void Dispose(bool disposing)
    {
        EditorSceneManager.activeSceneChangedInEditMode -= OnSceneChanged;
    }
#endif


    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (!renderingData.cameraData.isPreviewCamera)
        {
            lightPass.ConfigureInput(ScriptableRenderPassInput.Depth);
            renderer.EnqueuePass(lightPass);
        }
    }


    void ValidateShaders() 
    {
        if (!AddAlwaysIncludedShader("Hidden/BilateralBlur", ref bilateralBlur)) 
            Debug.LogError($"BilateralBlur shader missing! Make sure 'Hidden/BilateralBlur' is located somewhere in your project and included in 'Always Included Shaders'", this);

        if (!AddAlwaysIncludedShader("Hidden/VolumetricFog", ref volumetricFog))
            Debug.LogError($"VolumetricFog shader missing! Make sure 'Hidden/VolumetricFog' is located somewhere in your project and included in 'Always Included Shaders'", this);
    }


    static bool AddAlwaysIncludedShader(string shaderName, ref Shader shader)
    {
        if (shader != null)
            return true;

        shader = Shader.Find(shaderName);
        if (shader == null) 
            return false;
     
#if UNITY_EDITOR
        var graphicsSettingsObj = AssetDatabase.LoadAssetAtPath<GraphicsSettings>("ProjectSettings/GraphicsSettings.asset");
        var serializedObject = new SerializedObject(graphicsSettingsObj);
        var arrayProp = serializedObject.FindProperty("m_AlwaysIncludedShaders");
        bool hasShader = false;

        for (int i = 0; i < arrayProp.arraySize; ++i)
        {
            var arrayElem = arrayProp.GetArrayElementAtIndex(i);
            if (shader == arrayElem.objectReferenceValue)
            {
                hasShader = true;
                break;
            }
        }
     
        if (!hasShader)
        {
            int arrayIndex = arrayProp.arraySize;
            arrayProp.InsertArrayElementAtIndex(arrayIndex);
            var arrayElem = arrayProp.GetArrayElementAtIndex(arrayIndex);
            arrayElem.objectReferenceValue = shader;
     
            serializedObject.ApplyModifiedProperties();
     
            AssetDatabase.SaveAssets();
        }
#endif

        return true;
    }
}