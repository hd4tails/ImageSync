Shader "HDAssets/ImageCompress/PostInDCT"
{
    Properties
    {
        _TexYA("TargetImageYA", 2D) = "white" {}
        _TexC("TargetImageC", 2D) = "white" {}
        [Toggle]_UpdateFrag("Update", Int) = 0
    }

    SubShader
    {
        Lighting Off
        Blend One Zero

        Pass
        {
            name "Update"
            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #include "ImageLib.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 3.0
            sampler2D _TexYA;
            sampler2D _TexC;

            float4 frag(v2f_customrendertexture IN) : COLOR
            {
                // Desampling
                float2 pixel = uv2pixel(IN.localTexcoord.xy);
                float2 uv = pixel2uv(pixel);
                float2 valueYA = tex2D(_TexYA, uv);
                float2 valueC = tex2D(_TexC, uv);

                // YCBCRToRGB
                float4 ycbcra = float4(valueYA.x, valueC, valueYA.y);
                return float4(ycbcr2rgb(ycbcra.rgb), ycbcra.a) / 255;
            }
            ENDCG
        }
    }
}