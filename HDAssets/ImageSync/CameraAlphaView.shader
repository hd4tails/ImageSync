Shader "HDAssets/ImageCompress/CameraAlphaView"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "transparent" {}
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" }
        LOD 100

        Blend One One
        ZTest Off
        ZWrite OFf

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float2 uv : TEXCOORD0;
                float4 vertex : POSITION;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                float4 col = tex2D(_MainTex, i.uv);
                return saturate(col);
            }
            ENDCG
        }
    }
}
