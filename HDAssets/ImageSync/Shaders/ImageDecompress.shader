Shader "HDAssets/ImageCompress/ImageDecompress"
{
    Properties
    {
        _MainTex("TargetImage", 2D) = "white" {}
        [KeywordEnum(YA, CRCB)]
        _TARGET_TYPE("TargetType", float) = 0
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
            name "RemoveSizeGather"
            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #include "ImageLib.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 3.0
            sampler2D _MainTex;

            float4 frag(v2f_customrendertexture IN) : COLOR
            {
                float2 pixel = uv2pixel(IN.localTexcoord.xy);
                uint index = pixel.x + pixel.y * formatedSize().x; // 何番目のピクセルか
                float indexNum = formatedSize().x * formatedSize().y;
                return tex2D(_MainTex, pixel2uv(index2pixel(index + 1, formatedSize().x))); // 1px目にサイズが入力されているためずらす
            }
            ENDCG
        }
        
        Pass
        {
            name "DegatherXYData"
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

                float4 xSizeSep = tex2D(_SelfTexture2D, pixel2uv(index2pixel(0, formatedSize().x)));
                float4 ySizeSep = tex2D(_SelfTexture2D, pixel2uv(index2pixel(1, formatedSize().x)));
                uint xSize =
                    round(xSizeSep.x * 255)
                     + round(xSizeSep.y * 255) * 0x100
                     + round(xSizeSep.z * 255) * 0x10000
                     + round(xSizeSep.w * 255) * 0x1000000;
                uint ySize = 
                    round(ySizeSep.x)
                     + round(ySizeSep.y * 255) * 0x100
                     + round(ySizeSep.z * 255) * 0x10000
                     + round(ySizeSep.w * 255) * 0x1000000;
                float2 result = 0;
                
                if(index == 0)
                {
                    // xSizeを分解
                    result.x = xSize;
                    result.y = ySize;
                }
                else
                {
                    // x
                    if(index - 1 < ceil(xSize / 4.0) * 4)
                    {
                        // このPixelで扱うデータの位置の原点
                        uint setIndex = (index - 1) / 4;
                        switch((index - 1) - setIndex * 4)
                        {
                            case 0:
                                result.x = tex2D(_SelfTexture2D, pixel2uv(index2pixel(setIndex + 2, formatedSize().x))).x;
                                break;
                            case 1:
                                result.x = tex2D(_SelfTexture2D, pixel2uv(index2pixel(setIndex + 2, formatedSize().x))).y;
                                break;
                            case 2:
                                result.x = tex2D(_SelfTexture2D, pixel2uv(index2pixel(setIndex + 2, formatedSize().x))).z;
                                break;
                            case 3:
                                result.x = tex2D(_SelfTexture2D, pixel2uv(index2pixel(setIndex + 2, formatedSize().x))).w;
                                break;
                        }
                    }
                    // y
                    if(index - 1 - ceil(xSize / 4.0) * 4 < ceil(ySize / 4.0) * 4)
                    {
                        // このPixelで扱うデータの位置の原点
                        uint setIndex = (index - 1) / 4 + ceil(xSize / 4.0);
                        switch((index - 1) - (setIndex - ceil(xSize / 4.0)) * 4)
                        {
                            case 0:
                                result.y = tex2D(_SelfTexture2D, pixel2uv(index2pixel(setIndex + 2, formatedSize().x))).x;
                                break;
                            case 1:
                                result.y = tex2D(_SelfTexture2D, pixel2uv(index2pixel(setIndex + 2, formatedSize().x))).y;
                                break;
                            case 2:
                                result.y = tex2D(_SelfTexture2D, pixel2uv(index2pixel(setIndex + 2, formatedSize().x))).z;
                                break;
                            case 3:
                                result.y = tex2D(_SelfTexture2D, pixel2uv(index2pixel(setIndex + 2, formatedSize().x))).w;
                                break;
                        }
                    }
                }
                return result;
            }
            ENDCG
        }
        Pass
        {
            name "RemoveSizeXYData"
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
                return tex2D(_SelfTexture2D, pixel2uv(index2pixel(index + 1, formatedSize().x))); // 1px目にサイズが入力されているためずらす
            }
            ENDCG
        }
        

        Pass
        {
            name "DecodeHuffman"
            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #include "ImageLib.cginc"
            #include "HuffmanLib.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 3.0
            #pragma multi_compile _TARGET_TYPE_YA _TARGET_TYPE_CRCB

            // 1byteのデータから指定したindexの値を上位から取得する
            int getTargetBitData(int bitIndex, int value)
            {
                return (value >> (7 - bitIndex)) & 1;
            }

            float decodeHuffman(bool isX, int indexNum, int index)
            {
                #ifdef _TARGET_TYPE_YA
                    // YのACのhuffmanの各bit数での最小値のindexを求める
                    // Code
                    // bit数（index）は2=0となる
                    int AC_INV_HUFFMAN_VALPTR_TABLE[] = 
                    {
                        0,
                        2,
                        3,
                        6,
                        9,
                        11,
                        15,
                        18,
                        23,
                        28,
                        32,
                        0,
                        0,
                        36,
                        37
                    };
                    // YのACのhuffmanの各bit数での最小値を求める
                    int AC_INV_HUFFMAN_MINCODE_TABLE[] = 
                    {
                        0,      //0b00
                        4,      //0b100
                        10,     //0b1010
                        26,     //0b11010
                        58,     //0b111010
                        120,    //0b1111000
                        248,    //0b11111000
                        502,    //0b111110110
                        1014,   //0b1111110110
                        2038,   //0b11111110110
                        4084,   //0b111111110100
                        0,      //0b0
                        0,      //0b0
                        32704,  //0b111111111000000
                        65410   //0b1111111110000010
                    };
                    // YのACのhuffmanの各bit数での最大値を求める
                    // bit数（index）は2=0となる
                    int AC_INV_HUFFMAN_MAXCODE_TABLE[] = 
                    {
                        1,      //0b01
                        4,      //0b100
                        12,     //0b1100
                        28,     //0b11100
                        59,     //0b111011
                        123,    //0b1111011
                        250,    //0b11111010
                        506,    //0b111111010
                        1018,   //0b1111111010
                        2041,   //0b11111111001
                        4087,   //0b111111110111
                        0,      //0b0
                        0,      //0b0
                        32704,  //0b111111111000000
                        65534  //0b1111111111111110

                    };
                    int AC_INV_HUFFMAN_MAXCODE_TABLE_SIZE = 15;
                    int DC_INV_HUFFMAN_MAXCODE_TABLE_SIZE = 8;
                    int AC_INV_HUFFMAN_ASCENDING_ORDER_ZERONUM_TABLE[] = {0,0,0,0,0,1,0,1,2,3,4,0,1,5,6,0,2,7,1,3,8,9,10,0,2,4,11,12,1,5,13,15,2,3,6,7,8,0,0,1,1,1,1,1,2,2,2,2,2,2,3,3,3,3,3,3,3,4,4,4,4,4,4,4,4,5,5,5,5,5,5,5,5,6,6,6,6,6,6,6,6,7,7,7,7,7,7,7,7,8,8,8,8,8,8,8,8,9,9,9,9,9,9,9,9,9,10,10,10,10,10,10,10,10,10,11,11,11,11,11,11,11,11,11,12,12,12,12,12,12,12,12,12,13,13,13,13,13,13,13,13,13,14,14,14,14,14,14,14,14,14,14,15,15,15,15,15,15,15,15,15,15};
                    int AC_INV_HUFFMAN_ASCENDING_ORDER_CATEGORY_TABLE[] = {1,2,3,0,4,1,5,2,1,1,1,6,3,1,1,7,2,1,4,2,1,1,1,8,3,2,1,1,5,2,1,0,4,3,2,2,2,9,10,6,7,8,9,10,5,6,7,8,9,10,4,5,6,7,8,9,10,3,4,5,6,7,8,9,10,3,4,5,6,7,8,9,10,3,4,5,6,7,8,9,10,3,4,5,6,7,8,9,10,3,4,5,6,7,8,9,10,2,3,4,5,6,7,8,9,10,2,3,4,5,6,7,8,9,10,2,3,4,5,6,7,8,9,10,2,3,4,5,6,7,8,9,10,2,3,4,5,6,7,8,9,10,1,2,3,4,5,6,7,8,9,10,1,2,3,4,5,6,7,8,9,10};
                    int DC_INV_HUFFMAN_VALPTR_TABLE[] = 
                    {
                        0,
                        1,
                        6,
                        7,
                        8,
                        9,
                        10,
                        11
                    };
                    int DC_INV_HUFFMAN_MINCODE_TABLE[] = 
                    {
                        0,      //0b00
                        2,      //0b010
                        14,     //0b1110
                        30,     //0b11110
                        62,     //0b111110
                        126,    //0b1111110
                        254,    //0b11111110
                        510     //0b111111110
                    };
                    int DC_INV_HUFFMAN_MAXCODE_TABLE[] = 
                    {
                        0,      //0b00
                        6,      //0b110
                        14,     //0b1110
                        30,     //0b11110
                        62,     //0b111110
                        126,    //0b1111110
                        254,    //0b11111110
                        510     //0b111111110
                    };
                #else
                    // CのACのhuffmanの各bit数での最小値のindexを求める
                    // Code
                    // bit数（index）は2=0となる
                    int AC_INV_HUFFMAN_VALPTR_TABLE[] = 
                    {
                        0,
                        2,
                        3,
                        5,
                        9,
                        13,
                        16,
                        20,
                        27,
                        32,
                        36,
                        0,
                        40,
                        41,
                        43
                    };
                    // CのACのhuffmanの各bit数での最小値を求める
                    int AC_INV_HUFFMAN_MINCODE_TABLE[] = 
                    {
                        0,      //0b00
                        4,      //0b100
                        10,     //0b1010
                        24,     //0b11000
                        56,     //0b111000
                        120,    //0b1111000
                        246,    //0b11110110
                        500,    //0b111110100
                        1014,   //0b1111110110
                        2038,   //0b11111110110
                        4084,   //0b111111110100
                        0,      //0b0
                        16352,  //0b11111111100000
                        32706,  //0b111111111000010
                        65416   //0b1111111110001000
                    };
                    // CのACのhuffmanの各bit数での最大値を求める
                    // bit数（index）は2=0となる
                    int AC_INV_HUFFMAN_MAXCODE_TABLE[] = 
                    {
                        1,      //0b01
                        4,      //0b100
                        11,     //0b1011
                        27,     //0b11011
                        59,     //0b111011
                        122,    //0b1111010
                        249,    //0b11111001
                        506,    //0b111111010
                        1018,   //0b1111111010
                        2041,   //0b11111111001
                        4087,   //0b111111110111
                        0,      //0b0
                        16352,  //0b11111111100000
                        32707,  //0b111111111000011
                        65534   //0b1111111111111110
                    };
                    int AC_INV_HUFFMAN_MAXCODE_TABLE_SIZE = 15;
                    int DC_INV_HUFFMAN_MAXCODE_TABLE_SIZE = 10;
                    int AC_INV_HUFFMAN_ASCENDING_ORDER_ZERONUM_TABLE[] = {0,0,0,0,1,0,0,2,3,0,1,4,5,0,6,7,1,2,3,8,0,1,4,9,10,11,12,0,2,3,5,15,1,6,7,13,0,1,2,3,14,2,15,1,1,1,1,2,2,2,2,2,3,3,3,3,3,3,4,4,4,4,4,4,4,4,5,5,5,5,5,5,5,5,6,6,6,6,6,6,6,6,7,7,7,7,7,7,7,7,8,8,8,8,8,8,8,8,8,9,9,9,9,9,9,9,9,9,10,10,10,10,10,10,10,10,10,11,11,11,11,11,11,11,11,11,12,12,12,12,12,12,12,12,12,13,13,13,13,13,13,13,13,13,14,14,14,14,14,14,14,14,14,15,15,15,15,15,15,15,15,15};
                    int AC_INV_HUFFMAN_ASCENDING_ORDER_CATEGORY_TABLE[] = {0,1,2,3,1,4,5,1,1,6,2,1,1,7,1,1,3,2,2,1,8,4,2,1,1,1,1,9,3,3,2,0,5,2,2,1,10,6,4,4,1,5,1,7,8,9,10,6,7,8,9,10,5,6,7,8,9,10,3,4,5,6,7,8,9,10,3,4,5,6,7,8,9,10,3,4,5,6,7,8,9,10,3,4,5,6,7,8,9,10,2,3,4,5,6,7,8,9,10,2,3,4,5,6,7,8,9,10,2,3,4,5,6,7,8,9,10,2,3,4,5,6,7,8,9,10,2,3,4,5,6,7,8,9,10,2,3,4,5,6,7,8,9,10,2,3,4,5,6,7,8,9,10,2,3,4,5,6,7,8,9,10};
                    int DC_INV_HUFFMAN_VALPTR_TABLE[] = 
                    {
                        0,
                        3,
                        4,
                        5,
                        6,
                        7,
                        8,
                        9,
                        10,
                        11
                    };
                    int DC_INV_HUFFMAN_MINCODE_TABLE[] = 
                    {
                        0,      //0b00
                        6,      //0b110
                        14,     //0b1110
                        30,     //0b11110
                        62,     //0b111110
                        126,    //0b1111110
                        254,    //0b11111110
                        510,    //0b111111110
                        1022,   //0b1111111110
                        2046    //0b11111111110
                    };
                    int DC_INV_HUFFMAN_MAXCODE_TABLE[] = 
                    {
                        2,      //0b10
                        6,      //0b110
                        14,     //0b1110
                        30,     //0b11110
                        62,     //0b111110
                        126,    //0b1111110
                        254,    //0b11111110
                        510,    //0b111111110
                        1022,   //0b1111111110
                        2046    //0b11111111110
                    };
                #endif
                
                int nowBit = 0; // 現在の元データのbit位置
                int nowPixelValue = 0;
                int outputIndexInPacket = 0;
                int outputValue = 0;
                int count = 0;
                bool isEnd;
                [loop]
                while((nowBit >> 3) < indexNum)
                {
                    isEnd = false;
                    int huffmanCode = 0;
                    // 最大1パケット分走査する
                    if(fmod(outputIndexInPacket, (BLOCK_SIZE * BLOCK_SIZE)) < 0.5)
                    {
                        // DC
                        int huffmanCode = 0;
                        GET_BIT_DATA(huffmanCode)
                        // 2bit目からチェックする
                        for(int i = 0; i < DC_INV_HUFFMAN_MAXCODE_TABLE_SIZE; i++)
                        {
                            GET_BIT_DATA(huffmanCode)
                            if(huffmanCode <= DC_INV_HUFFMAN_MAXCODE_TABLE[i])
                            {
                                // 対象のリストが見つかったので、Codeを取り出す
                                int category = (DC_INV_HUFFMAN_VALPTR_TABLE[i] + (huffmanCode - DC_INV_HUFFMAN_MINCODE_TABLE[i]));
                                int additionalBit = 0;
                                for(int addBitInd = 0; addBitInd < category; addBitInd++)
                                {
                                    GET_BIT_DATA(additionalBit)
                                }
                                outputValue = fromAdditionalBit(additionalBit, category);
                                outputIndexInPacket++;
                                break;
                            }
                        }
                    }
                    else
                    {
                        // AC
                        int huffmanCode = 0;
                        GET_BIT_DATA(huffmanCode)

                        // 2bit目からチェックする
                        for(int i = 0; i < AC_INV_HUFFMAN_MAXCODE_TABLE_SIZE; i++)
                        {
                            GET_BIT_DATA(huffmanCode)

                            if(huffmanCode <= AC_INV_HUFFMAN_MAXCODE_TABLE[i])
                            {
                                // 対象のリストが見つかったので、Codeを取り出す
                                int j = (AC_INV_HUFFMAN_VALPTR_TABLE[i] + (huffmanCode - AC_INV_HUFFMAN_MINCODE_TABLE[i]));
                                int category = AC_INV_HUFFMAN_ASCENDING_ORDER_CATEGORY_TABLE[j];
                                int zeroNum = AC_INV_HUFFMAN_ASCENDING_ORDER_ZERONUM_TABLE[j];

                                if(category == EOB_CATEGORY && zeroNum == EOB_ZERONUM)
                                {
                                    // 以降0のため、次のBlockへ
                                    outputIndexInPacket = (int)round(((uint)outputIndexInPacket / (uint)(BLOCK_SIZE * BLOCK_SIZE)) + 1) * (BLOCK_SIZE * BLOCK_SIZE);
                                    outputValue = 0;
                                }
                                else if(category == ZRL_CATEGORY && zeroNum == ZRL_ZERONUM)
                                {
                                    // 以降16個0のため
                                    outputIndexInPacket += 16;
                                    outputValue = 0;
                                }
                                else
                                {
                                    // zeroNumの分だけ0を追加
                                    outputIndexInPacket += zeroNum;
                                    outputValue = 0;
                                    // この後に0でないデータが入るためここで一度判定
                                    if(outputIndexInPacket > index)
                                    {
                                        // 対象のデータが見つかったので終了
                                        isEnd = true;
                                        break;
                                    }
                                    int additionalBit = 0;
                                    for(int addBitInd = 0; addBitInd < category; addBitInd++)
                                    {
                                        GET_BIT_DATA(additionalBit)
                                    }

                                    outputValue = fromAdditionalBit(additionalBit, category);
                                    outputIndexInPacket++;
                                }

                                break;
                            }
                        }
                    }
                    if(outputIndexInPacket > index)
                    {
                        // 対象のデータが見つかったので終了
                        isEnd = true;
                    }
                    if(isEnd)
                    {
                        break;
                    }
                }
                return outputValue;
            }

            float2 frag(v2f_customrendertexture IN) : COLOR
            {
                // intは20bitくらいまでしか使えない、ビットシフトは使用しない

                float2 pixel = uv2pixel(IN.localTexcoord.xy);
                float index = pixel.x + pixel.y * formatedSize().x; // 何番目のピクセルか
                float indexNum = formatedSize().x * formatedSize().y;

                float2 output = 0;
                
                output.x = decodeHuffman(true, indexNum, index);
                output.y = decodeHuffman(false, indexNum, index);
                    
                return output;
            }
            ENDCG
        }
        Pass
        {
            name "RestoreDiff"
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
                float indexInBlock = fmod(index, (BLOCK_SIZE * BLOCK_SIZE)); // ブロックの中で何ピクセル目か
                float indexBlock = floor(index / (BLOCK_SIZE * BLOCK_SIZE)); // 何番目のブロックか
                float firstIndexInBlock = indexBlock * (BLOCK_SIZE * BLOCK_SIZE); // ブロックの先頭が何ピクセル目か
                
                float2 value = tex2D(_SelfTexture2D, pixel2uv(pixel));
                if(indexInBlock == 0)
                {
                    // DC
                    int baseBlock = floor(indexBlock / SEPARATE_DC_BLOCK) * SEPARATE_DC_BLOCK; // SEPARATE_DC_BLOCKブロックの先頭ブロック
                    value = 0;
                    float2 targetValue;
                    [unroll]
                    for(int i = 0; i < SEPARATE_DC_BLOCK; i++)
                    {
                        // unrollするために最大回数に指定
                        if(i <= (indexBlock - baseBlock))
                        {
                            // SEPARATE_DC_BLOCKブロックの最初から、今現在のブロックまでのループ
                            float targetBlockIndex = (baseBlock + i) * (BLOCK_SIZE * BLOCK_SIZE);
                            float2 targetDCPixel = float2(round(fmod(targetBlockIndex, formatedSize().x)), floor(round(targetBlockIndex) / formatedSize().x));
                            targetValue = tex2D(_SelfTexture2D, pixel2uv(targetDCPixel));
                            value -= targetValue; // そのブロックの値
                        }
                    }
                }
                return round(value);
            }
            ENDCG
        }
        Pass
        {
            name "Deserialize"
            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #include "ImageLib.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 3.0

            float2 frag(v2f_customrendertexture IN) : COLOR
            {
                float2 pixel = uv2pixel(IN.localTexcoord.xy);

                float blockMaxNum = floor(formatedSize().x / BLOCK_SIZE); // ブロックのx方向の最大数
                float2 blockBasePosNum = floor(pixel / BLOCK_SIZE); // ブロックの位置
                float2 blockInPos = pixel - blockBasePosNum * BLOCK_SIZE; // ブロック内での座標
                float blockBaseIndex = blockBasePosNum.x * (BLOCK_SIZE * BLOCK_SIZE) + blockBasePosNum.y * (BLOCK_SIZE * BLOCK_SIZE) * blockMaxNum; // 所属するブロックのはじめのインデックスの値
                float index = deSerializeIndex(blockInPos) + blockBaseIndex;
                float2 indexPos = float2(fmod(index, formatedSize().x), floor(index / formatedSize().x));
                float2 data = tex2D(_SelfTexture2D, pixel2uv(indexPos));
                return round(data);
            }
            ENDCG
        }

        Pass
        {
            name "InDCT"
            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #include "ImageLib.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 3.0
            #pragma multi_compile _TARGET_TYPE_YA _TARGET_TYPE_CRCB

            float2 frag(v2f_customrendertexture IN) : COLOR
            {
                float2 sum = 0;
                float2 pixel = uv2pixel(IN.localTexcoord.xy);
                float2 basePixel = floor(pixel / BLOCK_SIZE) * BLOCK_SIZE;
                float i = pixel.x - basePixel.x; // 周波数
                float j = pixel.y - basePixel.y; // 周波数
                for(int k=0; k < BLOCK_SIZE; k++) // データ
                {
                    for(int l=0; l < BLOCK_SIZE; l++) // データ
                    {
                        float2 targetUV = pixel2uv(basePixel + float2(k, l));
                        float2 value = tex2Dlod(_SelfTexture2D, float4(targetUV, 0, 0));
                        // dequantize
                        #ifdef _TARGET_TYPE_YA
                            value.x = value.x * quantizeValueY(float2(k, l), QUALITY);
                            value.y = value.y * quantizeValueY(float2(k, l), QUALITY);
                        #else
                            value.x = value.x * quantizeValueC(float2(k, l), QUALITY);
                            value.y = value.y * quantizeValueC(float2(k, l), QUALITY);
                        #endif
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
                return round(sum);
            }
            ENDCG
        }
    }
}