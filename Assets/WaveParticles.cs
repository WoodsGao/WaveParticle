using UnityEngine;
using System.Collections;
using System.Collections.Generic;
using System.Runtime.InteropServices;

[RequireComponent(typeof(Camera))]
public class WaveParticles : MonoBehaviour
{
    public float emitStep = 1;
    public float spreadSpeed = 1;
    public float spreadDecay = 0.9f;

    public int instanceCount = 10000;
    public Mesh instanceMesh;
    public Material instanceMaterial;
    public int subMeshIndex = 0;

    private ComputeBuffer alivePool;
    private ComputeBuffer deadPool;
    private ComputeBuffer positionBuffer;
    private ComputeBuffer dataBuffer;
    private ComputeBuffer argsBuffer;
    private uint[] args = new uint[5] { 0, 0, 0, 0, 0 };

    public int range;
    public Transform center;

    public ComputeShader computeShader;
    private int findAlivesKernel;
    private int updateAlivesKernel;
    private int processQueueKernel;

    public List<Transform> emitters;
    private Dictionary<Transform, Vector3> lastPostions = new Dictionary<Transform, Vector3>();

    public Material waterSurfaceMaterial;

    void OnEnable()
    {

        Debug.Log("init");
        findAlivesKernel = computeShader.FindKernel("FindAlives");
        updateAlivesKernel = computeShader.FindKernel("UpdateAlives");
        processQueueKernel = computeShader.FindKernel("ProcessQueue");

        InitBuffers();
        GetComponent<Camera>().cullingMask = 1 << LayerMask.NameToLayer("WaveParticle");
    }

    void Update()
    {
        Debug.Log("update");
        Vector4 worldToClip = new Vector4(1f / range, 1f / range, -center.position.x / range, -center.position.z / range);
        instanceMaterial.SetVector("_WorldToClip", worldToClip);
        computeShader.SetVector("_WorldToClip", worldToClip);
        computeShader.SetFloat("_SpreadSpeed", spreadSpeed);
        computeShader.SetFloat("_SpreadDecay", spreadDecay);
        var waveHeightST = new Vector4(worldToClip.x * 0.5f, worldToClip.y * 0.5f, worldToClip.z * 0.5f + 0.5f, worldToClip.w * 0.5f + 0.5f);
        Debug.Log("waveHeightST:" + waveHeightST);
        waterSurfaceMaterial.SetVector("_WaveHeight_ST", waveHeightST);
        // Update starting data buffer
        UpdateBuffers();
    }

    void InitBuffers()
    {
        argsBuffer = new ComputeBuffer(1, args.Length * sizeof(uint), ComputeBufferType.IndirectArguments);
        // Ensure submesh index is in range
        if (instanceMesh != null)
        {
            subMeshIndex = Mathf.Clamp(subMeshIndex, 0, instanceMesh.subMeshCount - 1);
            args[0] = (uint)instanceMesh.GetIndexCount(subMeshIndex);
            args[1] = (uint)0;
            args[2] = (uint)instanceMesh.GetIndexStart(subMeshIndex);
            args[3] = (uint)instanceMesh.GetBaseVertex(subMeshIndex);
        }
        else
        {
            args[0] = args[1] = args[2] = args[3] = 0;
        }
        argsBuffer.SetData(args);

        positionBuffer = new ComputeBuffer(instanceCount, 16);
        // worldX, worldZ, strength, theta
        Vector4[] positions = new Vector4[instanceCount];
        for (int i = 0; i < instanceCount; i++)
        {
            positions[i] = new Vector4(0, 0, 0, -1);
        }
        positionBuffer.SetData(positions);

        dataBuffer = new ComputeBuffer(instanceCount, 16);
        // speedX, speedZ, movedDistance, generation
        Vector4[] datas = new Vector4[instanceCount];
        for (int i = 0; i < instanceCount; i++)
        {
            datas[i] = new Vector4(-1, 0, 0, 0);
        }
        dataBuffer.SetData(datas);

        alivePool = new ComputeBuffer(instanceCount, sizeof(uint), ComputeBufferType.Append);
        alivePool.SetCounterValue(0);

        deadPool = new ComputeBuffer(instanceCount, sizeof(uint), ComputeBufferType.Append);
        deadPool.SetCounterValue(0);

        instanceMaterial.SetBuffer("_PositionBuffer", positionBuffer);
        instanceMaterial.SetBuffer("_AlivePool", alivePool);

        computeShader.SetBuffer(findAlivesKernel, "_PositionBuffer", positionBuffer);
        computeShader.SetBuffer(findAlivesKernel, "_DataBuffer", dataBuffer);
        computeShader.SetBuffer(findAlivesKernel, "_AlivePool", alivePool);
        computeShader.SetBuffer(findAlivesKernel, "_DeadPool", deadPool);

        computeShader.SetBuffer(updateAlivesKernel, "_PositionBuffer", positionBuffer);
        computeShader.SetBuffer(updateAlivesKernel, "_DataBuffer", dataBuffer);
        computeShader.SetBuffer(updateAlivesKernel, "_AlivePoolConsume", alivePool);
        computeShader.SetBuffer(updateAlivesKernel, "_DeadPoolConsume", deadPool);

        computeShader.SetBuffer(processQueueKernel, "_PositionBuffer", positionBuffer);
        computeShader.SetBuffer(processQueueKernel, "_DataBuffer", dataBuffer);
        computeShader.SetBuffer(processQueueKernel, "_AlivePool", alivePool);
        computeShader.SetBuffer(processQueueKernel, "_DeadPoolConsume", deadPool);
    }

    void UpdateBuffers()
    {
        computeShader.SetFloat("_DeltaTime", Time.deltaTime);

        // 剔除,区分dead和alive
        alivePool.SetCounterValue(0);
        deadPool.SetCounterValue(0);
        computeShader.Dispatch(findAlivesKernel, Mathf.CeilToInt((float)instanceCount / 8f), 1, 1);

        // 更新queue,并转移dead的到alive里面
        // worldX, worldZ, strength, theta
        var queue = new List<Vector4>();
        foreach (var emitter in emitters)
        {
            Vector2 pos = new Vector2(emitter.position.x, emitter.position.z);
            if (!lastPostions.ContainsKey(emitter))
            {
                lastPostions[emitter] = emitter.position;
            }
            else
            {
                Vector2 lastPos = new Vector2(lastPostions[emitter].x, lastPostions[emitter].z);
                Vector2 moveVec = pos - lastPos;
                float distance = moveVec.magnitude;
                if (distance > emitStep && emitter.position.y < 248.4)
                {
                    float strength = 1 - Mathf.Exp(-distance);
                    for (int i = 0; i < 8; i++)
                    {
                        queue.Add(new Vector4(pos.x, pos.y, strength, i / 8f));
                    }
                    lastPostions[emitter] = emitter.position;
                }
            }
        }
        if (queue.Count > 0)
        {
            var queueBuffer = new ComputeBuffer(queue.Count, 16);
            queueBuffer.SetData(queue.ToArray());
            computeShader.SetBuffer(processQueueKernel, "_QueueBuffer", queueBuffer);
            computeShader.Dispatch(processQueueKernel, Mathf.CeilToInt((float)queue.Count / 8f), 1, 1);
            queueBuffer.Dispose();
            queueBuffer.Release();
        }

        // 更新需要渲染的实例数量
        ComputeBuffer.CopyCount(alivePool, argsBuffer, sizeof(uint));
        int[] counter = new int[5];
        argsBuffer.GetData(counter);
        Debug.Log("count: " + counter[1]);

        // Render
        Graphics.DrawMeshInstancedIndirect(instanceMesh, subMeshIndex, instanceMaterial, new Bounds(Vector3.zero, new Vector3(300, 300, 300)), argsBuffer, layer: LayerMask.NameToLayer("WaveParticle"), camera: GetComponent<Camera>());


        if (counter[1] > 0)
        {
            // 更新alive,并使用dead生成新粒子
            computeShader.Dispatch(updateAlivesKernel, Mathf.CeilToInt((float)counter[1] / 8f), 1, 1);
        }
    }

    void ReleaseBuffer(ComputeBuffer buffer)
    {
        if (buffer != null)
        {
            buffer.Dispose();
            buffer.Release();
        }
        buffer = null;
    }

    void OnDisable()
    {
        ReleaseBuffer(argsBuffer);
        ReleaseBuffer(positionBuffer);
        ReleaseBuffer(dataBuffer);
        ReleaseBuffer(alivePool);
        ReleaseBuffer(deadPool);
    }
}