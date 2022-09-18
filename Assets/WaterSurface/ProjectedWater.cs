using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
public class ProjectedWater : MonoBehaviour
{
    Mesh CreateScreenGrid(int col, int row)
    {
        float _col = (float)col;
        float _row = (float)row;
        Mesh mesh = new Mesh();

        var vertices = new Vector3[(col + 1) * (row + 1)];
        for (int i = 0; i <= col; i++)
            for (int j = 0; j <= row; j++)
            {
                vertices[i * (row + 1) + j] = new Vector3((float)i / _col * 2 - 1, (float)j / _row * 2 - 1, 0);
            }

        mesh.vertices = vertices;

        var triangles = new int[(col + 1) * (row + 1) * 6];
        for (int i = 0; i < col; i++)
            for (int j = 0; j < row; j++)
            {
                int index = (i * row + j) * 6;
                int LT = i * (row + 1) + j;
                int RT = i * (row + 1) + j + 1;
                int LB = (i + 1) * (row + 1) + j;
                int RB = (i + 1) * (row + 1) + j + 1;

                triangles[index] = LT;
                triangles[index + 1] = RT;
                triangles[index + 2] = LB;

                triangles[index + 3] = RT;
                triangles[index + 4] = RB;
                triangles[index + 5] = LB;
            }
        mesh.triangles = triangles;

        mesh.bounds = new Bounds(new Vector3(0, 0, 0), new Vector3(float.MaxValue, float.MaxValue, float.MaxValue));

        return mesh;
    }

    void OnEnable()
    {
        MeshFilter filter = GetComponent<MeshFilter>();
        filter.mesh = CreateScreenGrid(160, 90);
    }


    void OnDisable()
    {
        MeshFilter filter = GetComponent<MeshFilter>();
        filter.mesh = null;
    }
}