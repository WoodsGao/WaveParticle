using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
[RequireComponent(typeof(Camera))]
public class DepthCaster : MonoBehaviour
{
    public Shader shader;

    void OnEnable()
    {
        var _camera = GetComponent<Camera>();
        _camera.SetReplacementShader(shader, "RenderType");
        Shader.SetGlobalTexture("_DepthCast", _camera.targetTexture);
        float size = _camera.orthographicSize * 2;
        Vector4 st = new Vector4(1 / size, 1 / size, -transform.position.x / size + 0.5f, -transform.position.z / size + 0.5f);
        Shader.SetGlobalVector("_DepthCast_ST", st);
    }

    void OnDisable()
    {
        GetComponent<Camera>().ResetReplacementShader();
        Shader.SetGlobalTexture("_DepthCast", null);
    }

    // Update is called once per frame
    void Update()
    {

    }
}
