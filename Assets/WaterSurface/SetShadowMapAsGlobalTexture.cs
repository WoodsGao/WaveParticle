using UnityEngine;
using UnityEngine.Rendering;
using UnityEditor;
using System.Collections;

[ExecuteInEditMode]
[RequireComponent(typeof(Light))]
public class SetShadowMapAsGlobalTexture : MonoBehaviour
{
    public string textureSemanticName = "_SunCascadedShadowMap";

    private RenderTexture shadowMapRenderTexture;
    private CommandBuffer commandBuffer;
    private Light lightComponent;

    void OnEnable()
    {
        lightComponent = GetComponent<Light>();
        SetupCommandBuffer();
    }

    void OnDisable()
    {
        lightComponent.RemoveCommandBuffer(LightEvent.AfterShadowMap, commandBuffer);
        ReleaseCommandBuffer();
    }

    [ContextMenu("Reset Shadow")]
    void Reset()
    {
        OnDisable();
        OnEnable();
    }

    void SetupCommandBuffer()
    {
        commandBuffer = new CommandBuffer();

        RenderTargetIdentifier shadowMapRenderTextureIdentifier = BuiltinRenderTextureType.CurrentActive;
        commandBuffer.SetGlobalTexture(textureSemanticName, shadowMapRenderTextureIdentifier);

        lightComponent.AddCommandBuffer(LightEvent.AfterShadowMap, commandBuffer);
    }

    void ReleaseCommandBuffer()
    {
        commandBuffer.Clear();
    }
}