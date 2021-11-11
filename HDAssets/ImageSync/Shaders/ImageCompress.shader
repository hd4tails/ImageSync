Shader "HDAssets/ImageCompress/ImageCompress"
{
    Properties
    {
        _MainTex("TargetImage", 2D) = "white" {}
        [Toggle]_isC("CrAndCb", Int) = 0
        [Toggle]_UpdateFrag("Update", Int) = 0
    }

    SubShader
    {
        Lighting Off
        Blend One Zero

        Pass
        {
            name "SelfCopy"
            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 3.0

            float4 frag(v2f_customrendertexture IN) : COLOR
            {
                return tex2D(_SelfTexture2D, IN.localTexcoord.xy);
            }
            ENDCG
        }

        Pass
        {
            name "PreDCT"
            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #include "ImageLib.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 3.0

            sampler2D _MainTex;
            int _isC;

            float2 frag(v2f_customrendertexture IN) : COLOR
            {
                // RGB_TO_YCBCR(0-255)
                float4 rgba = saturate(tex2D(_MainTex, IN.localTexcoord.xy)) * 255;
                float4 ycbcra = float4(rgb2ycbcr(rgba.rgb), rgba.a);

                // Sampling
                float2 sampledValue;
                if(_isC)
                {
                    sampledValue = ycbcra.yz;
                }
                else
                {
                    sampledValue = ycbcra.xw;
                }
                return round(sampledValue);
            }
            ENDCG
        }

        Pass
        {
            name "DCT"
            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #include "ImageLib.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 3.0
            
            int _isC;

            float2 frag(v2f_customrendertexture IN) : COLOR
            {
                float2 sum = 0;
                float2 pixel = uv2pixel(IN.localTexcoord.xy);
                // ブロック内での原点のPixel
                float2 basePixel = floor((pixel + 0.1) / BLOCK_SIZE) * BLOCK_SIZE;
                float k = pixel.x - basePixel.x; // x方向の周波数
                float l = pixel.y - basePixel.y; // y方向の周波数
                for(int i = 0; i < BLOCK_SIZE; i++)
                {
                    for(int j = 0; j < BLOCK_SIZE; j++)
                    {
                        float2 targetUV = pixel2uv(basePixel + float2(i, j));
                        float2 value = tex2D(_SelfTexture2D, targetUV);
                        {
                            float phiValue = phi(k, i, BLOCK_SIZE);
                            value *= phiValue;
                        }
                        {
                            float phiValue = phi(l, j, BLOCK_SIZE);
                            value *= phiValue;
                        }
                        sum.x += value.x;
                        sum.y += value.y;
                    }
                }
                
                // quantize
                if(_isC)
                {
                    sum.x = sum.x / quantizeValueC(pixel - basePixel, QUALITY);
                    sum.y = sum.y / quantizeValueC(pixel - basePixel, QUALITY);
                }
                else
                {
                    sum.x = sum.x / quantizeValueY(pixel - basePixel, QUALITY);
                    sum.y = sum.y / quantizeValueY(pixel - basePixel, QUALITY);
                }
                return round(sum);
            }
            ENDCG
        }
        Pass
        {
            name "Serialize"
            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #include "ImageLib.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 3.0

            float2 frag(v2f_customrendertexture IN) : COLOR
            {
                float2 pixel = uv2pixel(IN.localTexcoord.xy);
                float index = pixel.x + pixel.y * formatedSize().x;
                float targetBlockIndex = floor(index / (BLOCK_SIZE * BLOCK_SIZE));// どのブロックが対象か
                float blockMaxNum = floor(formatedSize().x / BLOCK_SIZE); // ブロックのx方向の最大数

                float2 targetBlockBasePos = float2(fmod(targetBlockIndex, blockMaxNum), floor(targetBlockIndex / blockMaxNum)) * BLOCK_SIZE;
                float2 targetBlockPos = serializePosition(fmod(index, BLOCK_SIZE * BLOCK_SIZE));
                float2 targetuv = pixel2uv(targetBlockPos + targetBlockBasePos);
                float2 data = tex2D(_SelfTexture2D, targetuv);
                return round(data);
            }
            ENDCG
        }

        Pass
        {
            name "CalcDiff"
            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #include "ImageLib.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 3.0

            float2 frag(v2f_customrendertexture IN) : COLOR
            {
                float2 pixel = uv2pixel(IN.localTexcoord.xy);
                float index = pixel.x + pixel.y * formatedSize().x; // 何番目のピクセルか
                float indexInBlock = index2pixel(index, (BLOCK_SIZE * BLOCK_SIZE)).x; // ブロックの中で何ピクセル目か
                float indexBlock = index2pixel(index, (BLOCK_SIZE * BLOCK_SIZE)).y; // 何番目のブロックか

                float2 value = tex2D(_SelfTexture2D, pixel2uv(pixel));
                if(indexInBlock == 0)
                {
                    // DC
                    if(fmod(indexBlock, SEPARATE_DC_BLOCK) == 0)
                    {
                        // SEPARATE_DC_BLOCK個のブロックおきにリセットする（0との差分とする）
                        value = -value;
                    }
                    else
                    {
                        // 一つ前のDCとの差分（一つ前-今）
                        float beforeBlockIndex = index - (BLOCK_SIZE * BLOCK_SIZE);
                        float2 beforeDCPixel = float2(round(fmod(beforeBlockIndex, formatedSize().x)), floor(round(beforeBlockIndex) / formatedSize().x));
                        value = tex2D(_SelfTexture2D, pixel2uv(beforeDCPixel)) - value;
                    }
                }
                return round(value);
            }
            ENDCG
        }
        Pass
        {
            name "CodeHuffmanYA"
            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #include "ImageLib.cginc"
            #include "HuffmanLib.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 3.0
            
            float2 frag(v2f_customrendertexture IN) : COLOR
            {
                // intは20bitくらいまでしか使えない

                float2 pixel = uv2pixel(IN.localTexcoord.xy);
                float index = pixel.x + pixel.y * formatedSize().x; // 何番目のピクセルか
                float indexNum = formatedSize().x * formatedSize().y;

                float2 output = 0;

                int targetByte = index;
                // ------------------------------------- X -----------------------------------------------
                {
                    int zeroCount = 0;
                    int outBits = 0;
                    int nowBit = 0; // 現在の元データのbit位置
                    bool isFinish = false;
                    [loop]
                    for(int i = 0; i < indexNum; i++)
                    {
                        int nowIndex = i;
                        float2 targetUV = pixel2uv(index2pixel(nowIndex, formatedSize().x));
                        int targetIndexInBlock = index2pixel(nowIndex, (BLOCK_SIZE * BLOCK_SIZE)).x; // ブロックの中で何ピクセル目か
                        float2 value = tex2D(_SelfTexture2D, targetUV);
                        
                        int inputValue = (int)value.x;

                        if(targetIndexInBlock == 0)
                        {
                            // DC
                            {
                                // x
                                int category = getCategory(inputValue);
                                int huffmanCode = getDCYHuffmanData(category);
                                int huffmanCodeSize = getDCYHuffmanSize(huffmanCode);
                                int additionalBit = getAdditionalBit(inputValue, category);

                                // -------------------------------
                                {
                                    int value = huffmanCode;
                                    int length = huffmanCodeSize;
                                    if(targetByte * 8 < nowBit + length)
                                    {
                                        if((targetByte + 1) * 8 <= nowBit + length)
                                        {
                                            int useBitLength = (targetByte + 1) * 8 - nowBit;
                                            isFinish = true;
                                            outBits = outBits << useBitLength;
                                            outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                        }
                                        else
                                        {
                                            int useBitLength = (nowBit + length) - targetByte * 8;
                                            int shiftBit = useBitLength;
                                            if(length < shiftBit)
                                            {
                                                shiftBit = length;
                                            }
                                            outBits = outBits << shiftBit;
                                            outBits = outBits | (value & ((1 << useBitLength) - 1));
                                        }
                                    }
                                    nowBit += length;
                                    if(isFinish)
                                    {
                                        break;
                                    }
                                }
                                // ------------------------------
                                // -------------------------------
                                {
                                    int value = additionalBit;
                                    int length = category;
                                    if(targetByte * 8 < nowBit + length)
                                    {
                                        if((targetByte + 1) * 8 <= nowBit + length)
                                        {
                                            int useBitLength = (targetByte + 1) * 8 - nowBit;
                                            isFinish = true;
                                            outBits = outBits << useBitLength;
                                            outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                        }
                                        else
                                        {
                                            int useBitLength = (nowBit + length) - targetByte * 8;
                                            int shiftBit = useBitLength;
                                            if(length < shiftBit)
                                            {
                                                shiftBit = length;
                                            }
                                            outBits = outBits << shiftBit;
                                            outBits = outBits | (value & ((1 << useBitLength) - 1));
                                        }
                                    }
                                    nowBit += length;
                                    if(isFinish)
                                    {
                                        break;
                                    }
                                }
                                // ------------------------------
                                zeroCount = 0;
                            }
                        }
                        else
                        {
                            // AC
                            {
                                // x
                                if(inputValue == 0)
                                {
                                    // データが0の場合
                                    if(targetIndexInBlock == 63)
                                    {
                                        // ブロック最後が0の場合
                                        // EOBを設定
                                        int category = EOB_CATEGORY;
                                        int huffmanCode = getACYHuffmanData(EOB_ZERONUM, category);
                                        int huffmanCodeSize = getACHuffmanSize(huffmanCode);
                                        int additionalBit = 0;
                                        // -------------------------------
                                        {
                                            int value = huffmanCode;
                                            int length = huffmanCodeSize;
                                            if(targetByte * 8 < nowBit + length)
                                            {
                                                if((targetByte + 1) * 8 <= nowBit + length)
                                                {
                                                    int useBitLength = (targetByte + 1) * 8 - nowBit;
                                                    isFinish = true;
                                                    outBits = outBits << useBitLength;
                                                    outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                                }
                                                else
                                                {
                                                    int useBitLength = (nowBit + length) - targetByte * 8;
                                                    int shiftBit = useBitLength;
                                                    if(length < shiftBit)
                                                    {
                                                        shiftBit = length;
                                                    }
                                                    outBits = outBits << shiftBit;
                                                    outBits = outBits | (value & ((1 << useBitLength) - 1));
                                                }
                                            }
                                            nowBit += length;
                                            if(isFinish)
                                            {
                                                break;
                                            }
                                        }
                                        // ------------------------------

                                        zeroCount = 0;
                                    }
                                    else
                                    {
                                        zeroCount ++;
                                    }
                                }
                                else
                                {
                                    // データが0でない場合
                                    while(zeroCount >= 16)
                                    {
                                        // 累積した0が16以上ある場合、16を切るまでZRLを設定
                                        int category = ZRL_CATEGORY;
                                        int huffmanCode = getACYHuffmanData(ZRL_ZERONUM, category);
                                        int huffmanCodeSize = getACHuffmanSize(huffmanCode);
                                        int additionalBit = 0;
                                        // -------------------------------
                                        {
                                            int value = huffmanCode;
                                            int length = huffmanCodeSize;
                                            if(targetByte * 8 < nowBit + length)
                                            {
                                                if((targetByte + 1) * 8 <= nowBit + length)
                                                {
                                                    int useBitLength = (targetByte + 1) * 8 - nowBit;
                                                    isFinish = true;
                                                    outBits = outBits << useBitLength;
                                                    outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                                }
                                                else
                                                {
                                                    int useBitLength = (nowBit + length) - targetByte * 8;
                                                    int shiftBit = useBitLength;
                                                    if(length < shiftBit)
                                                    {
                                                        shiftBit = length;
                                                    }
                                                    outBits = outBits << shiftBit;
                                                    outBits = outBits | (value & ((1 << useBitLength) - 1));
                                                }
                                            }
                                            nowBit += length;
                                            if(isFinish)
                                            {
                                                break;
                                            }
                                        }
                                        // ------------------------------

                                        zeroCount -= 16;
                                    }
                                    if(isFinish)
                                    {
                                        break;
                                    }
                                    {
                                        int category = getCategory(inputValue);
                                        int huffmanCode = getACYHuffmanData(zeroCount, category);
                                        int huffmanCodeSize = getACHuffmanSize(huffmanCode);
                                        int additionalBit = getAdditionalBit(inputValue, category);
                                        // -------------------------------
                                        {
                                            int value = huffmanCode;
                                            int length = huffmanCodeSize;
                                            if(targetByte * 8 < nowBit + length)
                                            {
                                                if((targetByte + 1) * 8 <= nowBit + length)
                                                {
                                                    int useBitLength = (targetByte + 1) * 8 - nowBit;
                                                    isFinish = true;
                                                    outBits = outBits << useBitLength;
                                                    outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                                }
                                                else
                                                {
                                                    int useBitLength = (nowBit + length) - targetByte * 8;
                                                    int shiftBit = useBitLength;
                                                    if(length < shiftBit)
                                                    {
                                                        shiftBit = length;
                                                    }
                                                    outBits = outBits << shiftBit;
                                                    outBits = outBits | (value & ((1 << useBitLength) - 1));
                                                }
                                            }
                                            nowBit += length;
                                            if(isFinish)
                                            {
                                                break;
                                            }
                                        }
                                        // ------------------------------
                                        // -------------------------------
                                        {
                                            int value = additionalBit;
                                            int length = category;
                                            if(targetByte * 8 < nowBit + length)
                                            {
                                                if((targetByte + 1) * 8 <= nowBit + length)
                                                {
                                                    int useBitLength = (targetByte + 1) * 8 - nowBit;
                                                    isFinish = true;
                                                    outBits = outBits << useBitLength;
                                                    outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                                }
                                                else
                                                {
                                                    int useBitLength = (nowBit + length) - targetByte * 8;
                                                    int shiftBit = useBitLength;
                                                    if(length < shiftBit)
                                                    {
                                                        shiftBit = length;
                                                    }
                                                    outBits = outBits << shiftBit;
                                                    outBits = outBits | (value & ((1 << useBitLength) - 1));
                                                }
                                            }
                                            nowBit += length;
                                            if(isFinish)
                                            {
                                                break;
                                            }
                                        }
                                        // ------------------------------

                                        zeroCount = 0;
                                    }
                                }
                            }
                        }
                    }
                    if(!isFinish)
                    {
                        outBits = outBits << ((targetByte + 1) * 8 - nowBit);
                    }
                    output.x = outBits / 255.0;
                }
                // ------------------------------------- Y -----------------------------------------------
                
                {
                    int zeroCount = 0;
                    int outBits = 0;
                    int nowBit = 0; // 現在の元データのbit位置
                    bool isFinish = false;
                    [loop]
                    for(int i = 0; i < indexNum; i++)
                    {
                        int nowIndex = i;
                        float2 targetUV = pixel2uv(index2pixel(nowIndex, formatedSize().x));
                        int targetIndexInBlock = index2pixel(nowIndex, (BLOCK_SIZE * BLOCK_SIZE)).x; // ブロックの中で何ピクセル目か
                        float2 value = tex2D(_SelfTexture2D, targetUV);
                        
                        int inputValue = (int)value.y;

                        if(targetIndexInBlock == 0)
                        {
                            // DC
                            {
                                // y
                                int category = getCategory(inputValue);
                                int huffmanCode = getDCYHuffmanData(category);
                                int huffmanCodeSize = getDCYHuffmanSize(huffmanCode);
                                int additionalBit = getAdditionalBit(inputValue, category);

                                // -------------------------------
                                {
                                    int value = huffmanCode;
                                    int length = huffmanCodeSize;
                                    if(targetByte * 8 < nowBit + length)
                                    {
                                        if((targetByte + 1) * 8 <= nowBit + length)
                                        {
                                            int useBitLength = (targetByte + 1) * 8 - nowBit;
                                            isFinish = true;
                                            outBits = outBits << useBitLength;
                                            outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                        }
                                        else
                                        {
                                            int useBitLength = (nowBit + length) - targetByte * 8;
                                            int shiftBit = useBitLength;
                                            if(length < shiftBit)
                                            {
                                                shiftBit = length;
                                            }
                                            outBits = outBits << shiftBit;
                                            outBits = outBits | (value & ((1 << useBitLength) - 1));
                                        }
                                    }
                                    nowBit += length;
                                    if(isFinish)
                                    {
                                        break;
                                    }
                                }
                                // ------------------------------
                                // -------------------------------
                                {
                                    int value = additionalBit;
                                    int length = category;
                                    if(targetByte * 8 < nowBit + length)
                                    {
                                        if((targetByte + 1) * 8 <= nowBit + length)
                                        {
                                            int useBitLength = (targetByte + 1) * 8 - nowBit;
                                            isFinish = true;
                                            outBits = outBits << useBitLength;
                                            outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                        }
                                        else
                                        {
                                            int useBitLength = (nowBit + length) - targetByte * 8;
                                            int shiftBit = useBitLength;
                                            if(length < shiftBit)
                                            {
                                                shiftBit = length;
                                            }
                                            outBits = outBits << shiftBit;
                                            outBits = outBits | (value & ((1 << useBitLength) - 1));
                                        }
                                    }
                                    nowBit += length;
                                    if(isFinish)
                                    {
                                        break;
                                    }
                                }
                                // ------------------------------
                                zeroCount = 0;
                            }
                        }
                        else
                        {
                            // AC
                            {
                                // y
                                if(inputValue == 0)
                                {
                                    // データが0の場合
                                    if(targetIndexInBlock == 63)
                                    {
                                        // ブロック最後が0の場合
                                        // EOBを設定
                                        int category = EOB_CATEGORY;
                                        int huffmanCode = getACYHuffmanData(EOB_ZERONUM, category);
                                        int huffmanCodeSize = getACHuffmanSize(huffmanCode);
                                        int additionalBit = 0;
                                        // -------------------------------
                                        {
                                            int value = huffmanCode;
                                            int length = huffmanCodeSize;
                                            if(targetByte * 8 < nowBit + length)
                                            {
                                                if((targetByte + 1) * 8 <= nowBit + length)
                                                {
                                                    int useBitLength = (targetByte + 1) * 8 - nowBit;
                                                    isFinish = true;
                                                    outBits = outBits << useBitLength;
                                                    outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                                }
                                                else
                                                {
                                                    int useBitLength = (nowBit + length) - targetByte * 8;
                                                    int shiftBit = useBitLength;
                                                    if(length < shiftBit)
                                                    {
                                                        shiftBit = length;
                                                    }
                                                    outBits = outBits << shiftBit;
                                                    outBits = outBits | (value & ((1 << useBitLength) - 1));
                                                }
                                            }
                                            nowBit += length;
                                            if(isFinish)
                                            {
                                                break;
                                            }
                                        }
                                        // ------------------------------

                                        zeroCount = 0;
                                    }
                                    else
                                    {
                                        zeroCount ++;
                                    }
                                }
                                else
                                {
                                    // データが0でない場合
                                    while(zeroCount >= 16)
                                    {
                                        // 累積した0が16以上ある場合、16を切るまでZRLを設定
                                        int category = ZRL_CATEGORY;
                                        int huffmanCode = getACYHuffmanData(ZRL_ZERONUM, category);
                                        int huffmanCodeSize = getACHuffmanSize(huffmanCode);
                                        int additionalBit = 0;
                                        // -------------------------------
                                        {
                                            int value = huffmanCode;
                                            int length = huffmanCodeSize;
                                            if(targetByte * 8 < nowBit + length)
                                            {
                                                if((targetByte + 1) * 8 <= nowBit + length)
                                                {
                                                    int useBitLength = (targetByte + 1) * 8 - nowBit;
                                                    isFinish = true;
                                                    outBits = outBits << useBitLength;
                                                    outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                                }
                                                else
                                                {
                                                    int useBitLength = (nowBit + length) - targetByte * 8;
                                                    int shiftBit = useBitLength;
                                                    if(length < shiftBit)
                                                    {
                                                        shiftBit = length;
                                                    }
                                                    outBits = outBits << shiftBit;
                                                    outBits = outBits | (value & ((1 << useBitLength) - 1));
                                                }
                                            }
                                            nowBit += length;
                                            if(isFinish)
                                            {
                                                break;
                                            }
                                        }
                                        // ------------------------------

                                        zeroCount -= 16;
                                    }
                                    if(isFinish)
                                    {
                                        break;
                                    }
                                    {
                                        int category = getCategory(inputValue);
                                        int huffmanCode = getACYHuffmanData(zeroCount, category);
                                        int huffmanCodeSize = getACHuffmanSize(huffmanCode);
                                        int additionalBit = getAdditionalBit(inputValue, category);
                                        // -------------------------------
                                        {
                                            int value = huffmanCode;
                                            int length = huffmanCodeSize;
                                            if(targetByte * 8 < nowBit + length)
                                            {
                                                if((targetByte + 1) * 8 <= nowBit + length)
                                                {
                                                    int useBitLength = (targetByte + 1) * 8 - nowBit;
                                                    isFinish = true;
                                                    outBits = outBits << useBitLength;
                                                    outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                                }
                                                else
                                                {
                                                    int useBitLength = (nowBit + length) - targetByte * 8;
                                                    int shiftBit = useBitLength;
                                                    if(length < shiftBit)
                                                    {
                                                        shiftBit = length;
                                                    }
                                                    outBits = outBits << shiftBit;
                                                    outBits = outBits | (value & ((1 << useBitLength) - 1));
                                                }
                                            }
                                            nowBit += length;
                                            if(isFinish)
                                            {
                                                break;
                                            }
                                        }
                                        // ------------------------------
                                        // -------------------------------
                                        {
                                            int value = additionalBit;
                                            int length = category;
                                            if(targetByte * 8 < nowBit + length)
                                            {
                                                if((targetByte + 1) * 8 <= nowBit + length)
                                                {
                                                    int useBitLength = (targetByte + 1) * 8 - nowBit;
                                                    isFinish = true;
                                                    outBits = outBits << useBitLength;
                                                    outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                                }
                                                else
                                                {
                                                    int useBitLength = (nowBit + length) - targetByte * 8;
                                                    int shiftBit = useBitLength;
                                                    if(length < shiftBit)
                                                    {
                                                        shiftBit = length;
                                                    }
                                                    outBits = outBits << shiftBit;
                                                    outBits = outBits | (value & ((1 << useBitLength) - 1));
                                                }
                                            }
                                            nowBit += length;
                                            if(isFinish)
                                            {
                                                break;
                                            }
                                        }
                                        // ------------------------------

                                        zeroCount = 0;
                                    }
                                }
                            }
                        }
                    }
                    if(!isFinish)
                    {
                        outBits = outBits << ((targetByte + 1) * 8 - nowBit);
                    }
                    output.y = outBits / 255.0;
                }
                return output;
            }
            ENDCG
        }
        
        Pass
        {
            name "CodeHuffmanC"
            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #include "ImageLib.cginc"
            #include "HuffmanLib.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 3.0
            
            float2 frag(v2f_customrendertexture IN) : COLOR
            {
                // intは20bitくらいまでしか使えない

                float2 pixel = uv2pixel(IN.localTexcoord.xy);
                float index = pixel.x + pixel.y * formatedSize().x; // 何番目のピクセルか
                float indexNum = formatedSize().x * formatedSize().y;

                float2 output = 0;

                int targetByte = index;
                // ------------------------------------- X -----------------------------------------------
                {
                    int zeroCount = 0;
                    int outBits = 0;
                    int nowBit = 0; // 現在の元データのbit位置
                    bool isFinish = false;
                    [loop]
                    for(int i = 0; i < indexNum; i++)
                    {
                        int nowIndex = i;
                        float2 targetUV = pixel2uv(index2pixel(nowIndex, formatedSize().x));
                        int targetIndexInBlock = index2pixel(nowIndex, (BLOCK_SIZE * BLOCK_SIZE)).x; // ブロックの中で何ピクセル目か
                        float2 value = tex2D(_SelfTexture2D, targetUV);
                        
                        int inputValue = (int)value.x;

                        if(targetIndexInBlock == 0)
                        {
                            // DC
                            {
                                // x
                                int category = getCategory(inputValue);
                                int huffmanCode = getDCCHuffmanData(category);
                                int huffmanCodeSize = getDCCHuffmanSize(huffmanCode);
                                int additionalBit = getAdditionalBit(inputValue, category);

                                // -------------------------------
                                {
                                    int value = huffmanCode;
                                    int length = huffmanCodeSize;
                                    if(targetByte * 8 < nowBit + length)
                                    {
                                        if((targetByte + 1) * 8 <= nowBit + length)
                                        {
                                            int useBitLength = (targetByte + 1) * 8 - nowBit;
                                            isFinish = true;
                                            outBits = outBits << useBitLength;
                                            outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                        }
                                        else
                                        {
                                            int useBitLength = (nowBit + length) - targetByte * 8;
                                            int shiftBit = useBitLength;
                                            if(length < shiftBit)
                                            {
                                                shiftBit = length;
                                            }
                                            outBits = outBits << shiftBit;
                                            outBits = outBits | (value & ((1 << useBitLength) - 1));
                                        }
                                    }
                                    nowBit += length;
                                    if(isFinish)
                                    {
                                        break;
                                    }
                                }
                                // ------------------------------
                                // -------------------------------
                                {
                                    int value = additionalBit;
                                    int length = category;
                                    if(targetByte * 8 < nowBit + length)
                                    {
                                        if((targetByte + 1) * 8 <= nowBit + length)
                                        {
                                            int useBitLength = (targetByte + 1) * 8 - nowBit;
                                            isFinish = true;
                                            outBits = outBits << useBitLength;
                                            outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                        }
                                        else
                                        {
                                            int useBitLength = (nowBit + length) - targetByte * 8;
                                            int shiftBit = useBitLength;
                                            if(length < shiftBit)
                                            {
                                                shiftBit = length;
                                            }
                                            outBits = outBits << shiftBit;
                                            outBits = outBits | (value & ((1 << useBitLength) - 1));
                                        }
                                    }
                                    nowBit += length;
                                    if(isFinish)
                                    {
                                        break;
                                    }
                                }
                                // ------------------------------
                                zeroCount = 0;
                            }
                        }
                        else
                        {
                            // AC
                            {
                                // x
                                if(inputValue == 0)
                                {
                                    // データが0の場合
                                    if(targetIndexInBlock == 63)
                                    {
                                        // ブロック最後が0の場合
                                        // EOBを設定
                                        int category = EOB_CATEGORY;
                                        int huffmanCode = getACCHuffmanData(EOB_ZERONUM, category);
                                        int huffmanCodeSize = getACHuffmanSize(huffmanCode);
                                        int additionalBit = 0;
                                        // -------------------------------
                                        {
                                            int value = huffmanCode;
                                            int length = huffmanCodeSize;
                                            if(targetByte * 8 < nowBit + length)
                                            {
                                                if((targetByte + 1) * 8 <= nowBit + length)
                                                {
                                                    int useBitLength = (targetByte + 1) * 8 - nowBit;
                                                    isFinish = true;
                                                    outBits = outBits << useBitLength;
                                                    outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                                }
                                                else
                                                {
                                                    int useBitLength = (nowBit + length) - targetByte * 8;
                                                    int shiftBit = useBitLength;
                                                    if(length < shiftBit)
                                                    {
                                                        shiftBit = length;
                                                    }
                                                    outBits = outBits << shiftBit;
                                                    outBits = outBits | (value & ((1 << useBitLength) - 1));
                                                }
                                            }
                                            nowBit += length;
                                            if(isFinish)
                                            {
                                                break;
                                            }
                                        }
                                        // ------------------------------

                                        zeroCount = 0;
                                    }
                                    else
                                    {
                                        zeroCount ++;
                                    }
                                }
                                else
                                {
                                    // データが0でない場合
                                    while(zeroCount >= 16)
                                    {
                                        // 累積した0が16以上ある場合、16を切るまでZRLを設定
                                        int category = ZRL_CATEGORY;
                                        int huffmanCode = getACCHuffmanData(ZRL_ZERONUM, category);
                                        int huffmanCodeSize = getACHuffmanSize(huffmanCode);
                                        int additionalBit = 0;
                                        // -------------------------------
                                        {
                                            int value = huffmanCode;
                                            int length = huffmanCodeSize;
                                            if(targetByte * 8 < nowBit + length)
                                            {
                                                if((targetByte + 1) * 8 <= nowBit + length)
                                                {
                                                    int useBitLength = (targetByte + 1) * 8 - nowBit;
                                                    isFinish = true;
                                                    outBits = outBits << useBitLength;
                                                    outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                                }
                                                else
                                                {
                                                    int useBitLength = (nowBit + length) - targetByte * 8;
                                                    int shiftBit = useBitLength;
                                                    if(length < shiftBit)
                                                    {
                                                        shiftBit = length;
                                                    }
                                                    outBits = outBits << shiftBit;
                                                    outBits = outBits | (value & ((1 << useBitLength) - 1));
                                                }
                                            }
                                            nowBit += length;
                                            if(isFinish)
                                            {
                                                break;
                                            }
                                        }
                                        // ------------------------------

                                        zeroCount -= 16;
                                    }
                                    if(isFinish)
                                    {
                                        break;
                                    }
                                    {
                                        int category = getCategory(inputValue);
                                        int huffmanCode = getACCHuffmanData(zeroCount, category);
                                        int huffmanCodeSize = getACHuffmanSize(huffmanCode);
                                        int additionalBit = getAdditionalBit(inputValue, category);
                                        // -------------------------------
                                        {
                                            int value = huffmanCode;
                                            int length = huffmanCodeSize;
                                            if(targetByte * 8 < nowBit + length)
                                            {
                                                if((targetByte + 1) * 8 <= nowBit + length)
                                                {
                                                    int useBitLength = (targetByte + 1) * 8 - nowBit;
                                                    isFinish = true;
                                                    outBits = outBits << useBitLength;
                                                    outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                                }
                                                else
                                                {
                                                    int useBitLength = (nowBit + length) - targetByte * 8;
                                                    int shiftBit = useBitLength;
                                                    if(length < shiftBit)
                                                    {
                                                        shiftBit = length;
                                                    }
                                                    outBits = outBits << shiftBit;
                                                    outBits = outBits | (value & ((1 << useBitLength) - 1));
                                                }
                                            }
                                            nowBit += length;
                                            if(isFinish)
                                            {
                                                break;
                                            }
                                        }
                                        // ------------------------------
                                        // -------------------------------
                                        {
                                            int value = additionalBit;
                                            int length = category;
                                            if(targetByte * 8 < nowBit + length)
                                            {
                                                if((targetByte + 1) * 8 <= nowBit + length)
                                                {
                                                    int useBitLength = (targetByte + 1) * 8 - nowBit;
                                                    isFinish = true;
                                                    outBits = outBits << useBitLength;
                                                    outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                                }
                                                else
                                                {
                                                    int useBitLength = (nowBit + length) - targetByte * 8;
                                                    int shiftBit = useBitLength;
                                                    if(length < shiftBit)
                                                    {
                                                        shiftBit = length;
                                                    }
                                                    outBits = outBits << shiftBit;
                                                    outBits = outBits | (value & ((1 << useBitLength) - 1));
                                                }
                                            }
                                            nowBit += length;
                                            if(isFinish)
                                            {
                                                break;
                                            }
                                        }
                                        // ------------------------------

                                        zeroCount = 0;
                                    }
                                }
                            }
                        }
                    }
                    if(!isFinish)
                    {
                        outBits = outBits << ((targetByte + 1) * 8 - nowBit);
                    }
                    output.x = outBits / 255.0;
                }
                // ------------------------------------- Y -----------------------------------------------
                
                {
                    int zeroCount = 0;
                    int outBits = 0;
                    int nowBit = 0; // 現在の元データのbit位置
                    bool isFinish = false;
                    [loop]
                    for(int i = 0; i < indexNum; i++)
                    {
                        int nowIndex = i;
                        float2 targetUV = pixel2uv(index2pixel(nowIndex, formatedSize().x));
                        int targetIndexInBlock = index2pixel(nowIndex, (BLOCK_SIZE * BLOCK_SIZE)).x; // ブロックの中で何ピクセル目か
                        float2 value = tex2D(_SelfTexture2D, targetUV);
                        
                        int inputValue = (int)value.y;

                        if(targetIndexInBlock == 0)
                        {
                            // DC
                            {
                                // y
                                int category = getCategory(inputValue);
                                int huffmanCode = getDCCHuffmanData(category);
                                int huffmanCodeSize = getDCCHuffmanSize(huffmanCode);
                                int additionalBit = getAdditionalBit(inputValue, category);

                                // -------------------------------
                                {
                                    int value = huffmanCode;
                                    int length = huffmanCodeSize;
                                    if(targetByte * 8 < nowBit + length)
                                    {
                                        if((targetByte + 1) * 8 <= nowBit + length)
                                        {
                                            int useBitLength = (targetByte + 1) * 8 - nowBit;
                                            isFinish = true;
                                            outBits = outBits << useBitLength;
                                            outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                        }
                                        else
                                        {
                                            int useBitLength = (nowBit + length) - targetByte * 8;
                                            int shiftBit = useBitLength;
                                            if(length < shiftBit)
                                            {
                                                shiftBit = length;
                                            }
                                            outBits = outBits << shiftBit;
                                            outBits = outBits | (value & ((1 << useBitLength) - 1));
                                        }
                                    }
                                    nowBit += length;
                                    if(isFinish)
                                    {
                                        break;
                                    }
                                }
                                // ------------------------------
                                // -------------------------------
                                {
                                    int value = additionalBit;
                                    int length = category;
                                    if(targetByte * 8 < nowBit + length)
                                    {
                                        if((targetByte + 1) * 8 <= nowBit + length)
                                        {
                                            int useBitLength = (targetByte + 1) * 8 - nowBit;
                                            isFinish = true;
                                            outBits = outBits << useBitLength;
                                            outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                        }
                                        else
                                        {
                                            int useBitLength = (nowBit + length) - targetByte * 8;
                                            int shiftBit = useBitLength;
                                            if(length < shiftBit)
                                            {
                                                shiftBit = length;
                                            }
                                            outBits = outBits << shiftBit;
                                            outBits = outBits | (value & ((1 << useBitLength) - 1));
                                        }
                                    }
                                    nowBit += length;
                                    if(isFinish)
                                    {
                                        break;
                                    }
                                }
                                // ------------------------------
                                zeroCount = 0;
                            }
                        }
                        else
                        {
                            // AC
                            {
                                // y
                                if(inputValue == 0)
                                {
                                    // データが0の場合
                                    if(targetIndexInBlock == 63)
                                    {
                                        // ブロック最後が0の場合
                                        // EOBを設定
                                        int category = EOB_CATEGORY;
                                        int huffmanCode = getACCHuffmanData(EOB_ZERONUM, category);
                                        int huffmanCodeSize = getACHuffmanSize(huffmanCode);
                                        int additionalBit = 0;
                                        // -------------------------------
                                        {
                                            int value = huffmanCode;
                                            int length = huffmanCodeSize;
                                            if(targetByte * 8 < nowBit + length)
                                            {
                                                if((targetByte + 1) * 8 <= nowBit + length)
                                                {
                                                    int useBitLength = (targetByte + 1) * 8 - nowBit;
                                                    isFinish = true;
                                                    outBits = outBits << useBitLength;
                                                    outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                                }
                                                else
                                                {
                                                    int useBitLength = (nowBit + length) - targetByte * 8;
                                                    int shiftBit = useBitLength;
                                                    if(length < shiftBit)
                                                    {
                                                        shiftBit = length;
                                                    }
                                                    outBits = outBits << shiftBit;
                                                    outBits = outBits | (value & ((1 << useBitLength) - 1));
                                                }
                                            }
                                            nowBit += length;
                                            if(isFinish)
                                            {
                                                break;
                                            }
                                        }
                                        // ------------------------------

                                        zeroCount = 0;
                                    }
                                    else
                                    {
                                        zeroCount ++;
                                    }
                                }
                                else
                                {
                                    // データが0でない場合
                                    while(zeroCount >= 16)
                                    {
                                        // 累積した0が16以上ある場合、16を切るまでZRLを設定
                                        int category = ZRL_CATEGORY;
                                        int huffmanCode = getACCHuffmanData(ZRL_ZERONUM, category);
                                        int huffmanCodeSize = getACHuffmanSize(huffmanCode);
                                        int additionalBit = 0;
                                        // -------------------------------
                                        {
                                            int value = huffmanCode;
                                            int length = huffmanCodeSize;
                                            if(targetByte * 8 < nowBit + length)
                                            {
                                                if((targetByte + 1) * 8 <= nowBit + length)
                                                {
                                                    int useBitLength = (targetByte + 1) * 8 - nowBit;
                                                    isFinish = true;
                                                    outBits = outBits << useBitLength;
                                                    outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                                }
                                                else
                                                {
                                                    int useBitLength = (nowBit + length) - targetByte * 8;
                                                    int shiftBit = useBitLength;
                                                    if(length < shiftBit)
                                                    {
                                                        shiftBit = length;
                                                    }
                                                    outBits = outBits << shiftBit;
                                                    outBits = outBits | (value & ((1 << useBitLength) - 1));
                                                }
                                            }
                                            nowBit += length;
                                            if(isFinish)
                                            {
                                                break;
                                            }
                                        }
                                        // ------------------------------

                                        zeroCount -= 16;
                                    }
                                    if(isFinish)
                                    {
                                        break;
                                    }
                                    {
                                        int category = getCategory(inputValue);
                                        int huffmanCode = getACCHuffmanData(zeroCount, category);
                                        int huffmanCodeSize = getACHuffmanSize(huffmanCode);
                                        int additionalBit = getAdditionalBit(inputValue, category);
                                        // -------------------------------
                                        {
                                            int value = huffmanCode;
                                            int length = huffmanCodeSize;
                                            if(targetByte * 8 < nowBit + length)
                                            {
                                                if((targetByte + 1) * 8 <= nowBit + length)
                                                {
                                                    int useBitLength = (targetByte + 1) * 8 - nowBit;
                                                    isFinish = true;
                                                    outBits = outBits << useBitLength;
                                                    outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                                }
                                                else
                                                {
                                                    int useBitLength = (nowBit + length) - targetByte * 8;
                                                    int shiftBit = useBitLength;
                                                    if(length < shiftBit)
                                                    {
                                                        shiftBit = length;
                                                    }
                                                    outBits = outBits << shiftBit;
                                                    outBits = outBits | (value & ((1 << useBitLength) - 1));
                                                }
                                            }
                                            nowBit += length;
                                            if(isFinish)
                                            {
                                                break;
                                            }
                                        }
                                        // ------------------------------
                                        // -------------------------------
                                        {
                                            int value = additionalBit;
                                            int length = category;
                                            if(targetByte * 8 < nowBit + length)
                                            {
                                                if((targetByte + 1) * 8 <= nowBit + length)
                                                {
                                                    int useBitLength = (targetByte + 1) * 8 - nowBit;
                                                    isFinish = true;
                                                    outBits = outBits << useBitLength;
                                                    outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);
                                                }
                                                else
                                                {
                                                    int useBitLength = (nowBit + length) - targetByte * 8;
                                                    int shiftBit = useBitLength;
                                                    if(length < shiftBit)
                                                    {
                                                        shiftBit = length;
                                                    }
                                                    outBits = outBits << shiftBit;
                                                    outBits = outBits | (value & ((1 << useBitLength) - 1));
                                                }
                                            }
                                            nowBit += length;
                                            if(isFinish)
                                            {
                                                break;
                                            }
                                        }
                                        // ------------------------------

                                        zeroCount = 0;
                                    }
                                }
                            }
                        }
                    }
                    if(!isFinish)
                    {
                        outBits = outBits << ((targetByte + 1) * 8 - nowBit);
                    }
                    output.y = outBits / 255.0;
                }
                return output;
            }
            ENDCG
        }
        Pass
        {
            name "CountXYData"
            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #include "ImageLib.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 3.0

            float2 frag(v2f_customrendertexture IN) : COLOR
            {
                float2 pixel = uv2pixel(IN.localTexcoord.xy);
                uint index = pixel.x + pixel.y * formatedSize().x; // 何番目のピクセルか
                float indexNum = formatedSize().x * formatedSize().y;

                uint xSize = 0;
                uint ySize = 0;
                if(index == 0)
                {
                    [loop]
                    for(int i = indexNum - 1; i >= 0; i--)
                    {
                        float2 checkValue = tex2D(_SelfTexture2D, pixel2uv(index2pixel(i, formatedSize().x)));
                        if(xSize == 0)
                        {
                            if(checkValue.x != 0)
                            {
                                xSize = i + 1;
                            }
                        }
                        if(ySize == 0)
                        {
                            if(checkValue.y != 0)
                            {
                                ySize = i + 1;
                            }
                        }
                        if(xSize != 0 && ySize != 0)
                        {
                            break;
                        }
                    }
                    return float2(xSize, ySize);
                }
                else
                {
                    return tex2D(_SelfTexture2D, pixel2uv(index2pixel(index - 1, formatedSize().x))); // 1px目にサイズを入力するためずらす
                }
            }
            ENDCG
        }
        Pass
        {
            name "GatherXYData"
            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #include "ImageLib.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 3.0

            float4 frag(v2f_customrendertexture IN) : COLOR
            {
                float2 pixel = uv2pixel(IN.localTexcoord.xy);
                uint index = pixel.x + pixel.y * formatedSize().x; // 何番目のピクセルか
                float indexNum = formatedSize().x * formatedSize().y;

                float2 size = tex2D(_SelfTexture2D, pixel2uv(index2pixel(0, formatedSize().x)));
                uint xSize = size.x;
                uint ySize = size.y;
                float4 result = 0;

                if(index == 0)
                {
                    // xSizeを分解
                    result.x = ((xSize      ) & 0xFF) / 255.0;
                    result.y = ((xSize >> 8 ) & 0xFF) / 255.0;
                    result.z = ((xSize >> 16) & 0xFF) / 255.0;
                    result.a = ((xSize >> 24) & 0xFF) / 255.0;
                }
                else if(index == 1)
                {
                    // ySizeを分解
                    result.x = ((ySize      ) & 0xFF) / 255.0;
                    result.y = ((ySize >> 8 ) & 0xFF) / 255.0;
                    result.z = ((ySize >> 16) & 0xFF) / 255.0;
                    result.a = ((ySize >> 24) & 0xFF) / 255.0;
                }
                else
                {
                    // このPixelで扱うデータの位置の原点
                    uint setIndex = (index - 2) * 4;
                    if(setIndex < xSize)
                    {
                        // xのデータをセットする
                        // データは2つめから入っているため+1
                        result.x = tex2D(_SelfTexture2D, pixel2uv(index2pixel(setIndex + 1, formatedSize().x))).x;
                        result.y = tex2D(_SelfTexture2D, pixel2uv(index2pixel(setIndex + 2, formatedSize().x))).x;
                        result.z = tex2D(_SelfTexture2D, pixel2uv(index2pixel(setIndex + 3, formatedSize().x))).x;
                        result.w = tex2D(_SelfTexture2D, pixel2uv(index2pixel(setIndex + 4, formatedSize().x))).x;
                    }
                    else
                    {
                        setIndex = ((index - ceil(xSize / 4.0)) - 2) * 4;
                        if(setIndex < ySize)
                        {
                            // yのデータをセットする
                            result.x = tex2D(_SelfTexture2D, pixel2uv(index2pixel(setIndex + 1, formatedSize().x))).y;
                            result.y = tex2D(_SelfTexture2D, pixel2uv(index2pixel(setIndex + 2, formatedSize().x))).y;
                            result.z = tex2D(_SelfTexture2D, pixel2uv(index2pixel(setIndex + 3, formatedSize().x))).y;
                            result.w = tex2D(_SelfTexture2D, pixel2uv(index2pixel(setIndex + 4, formatedSize().x))).y;
                        }
                    }
                }
                return result;
            }
            ENDCG
        }
        Pass
        {
            name "CountGatherData"
            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #include "ImageLib.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 3.0

            float4 frag(v2f_customrendertexture IN) : COLOR
            {
                float2 pixel = uv2pixel(IN.localTexcoord.xy);
                uint index = pixel.x + pixel.y * formatedSize().x; // 何番目のピクセルか
                float indexNum = formatedSize().x * formatedSize().y;

                uint size = 0;
                if(index == 0)
                {
                    [loop]
                    for(int i = indexNum - 1; i >= 0; i--)
                    {
                        float4 checkValue = tex2D(_SelfTexture2D, pixel2uv(index2pixel(i, formatedSize().x)));
                        if(checkValue.x != 0 || checkValue.y != 0 || checkValue.z != 0 || checkValue.w != 0)
                        {
                            size = i + 1;
                            break;
                        }
                    }
                    // sizeを分解
                    float4 result;
                    result.x = ((size      ) & 0xFF) / 255.0;
                    result.y = ((size >> 8 ) & 0xFF) / 255.0;
                    result.z = ((size >> 16) & 0xFF) / 255.0;
                    result.a = ((size >> 24) & 0xFF) / 255.0;
                    return result;
                }
                else
                {
                    return tex2D(_SelfTexture2D, pixel2uv(index2pixel(index - 1, formatedSize().x))); // 1px目にサイズを入力するためずらす
                }
            }
            ENDCG
        }
    }

}