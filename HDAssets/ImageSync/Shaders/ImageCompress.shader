Shader "HDAssets/ImageCompress/ImageCompress"
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
            name "PreDCT"
            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #include "ImageLib.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 3.0
            #pragma multi_compile _TARGET_TYPE_YA _TARGET_TYPE_CRCB

            sampler2D _MainTex;

            float2 frag(v2f_customrendertexture IN) : COLOR
            {
                // RGB_TO_YCBCR(0-255)
                float4 rgba = saturate(tex2D(_MainTex, IN.localTexcoord.xy)) * 255;
                float4 ycbcra = float4(rgb2ycbcr(rgba.rgb), rgba.a);

                // Sampling
                float2 sampledValue;
                #ifdef _TARGET_TYPE_YA
                    sampledValue = ycbcra.xw;
                #else
                    sampledValue = ycbcra.yz;
                #endif
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
            #pragma multi_compile _TARGET_TYPE_YA _TARGET_TYPE_CRCB

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
                #ifdef _TARGET_TYPE_YA
                    sum.x = sum.x / quantizeValueY(pixel - basePixel, QUALITY);
                    sum.y = sum.y / quantizeValueY(pixel - basePixel, QUALITY);
                #else
                    sum.x = sum.x / quantizeValueC(pixel - basePixel, QUALITY);
                    sum.y = sum.y / quantizeValueC(pixel - basePixel, QUALITY);
                #endif
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
                    if(fmod(indexBlock, SEPARATE_DC_BLOCK) == 0)
                    {
                        // DC
                        // SEPARATE_DC_BLOCK個のブロックおきにリセットする（0との差分とする）
                        value = -value;
                    }
                    else
                    {
                        // AC
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
            name "CodeHuffman"
            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"
            #include "ImageLib.cginc"
            #include "HuffmanLib.cginc"
            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 3.0
            #pragma multi_compile _TARGET_TYPE_YA _TARGET_TYPE_CRCB
        
            #ifdef _TARGET_TYPE_YA    
                // YのDCのHuffmanのbit数を取得する
                // 0のとき2bit、それ以外のとき最低3bit
                int getDCHuffmanSize(int huffmanValue)
                {
                    int size = getBitLengthNum(huffmanValue);
                    return size == 0 ? 2 : (size < 3 ? 3: size);
                }
            #else
                // CのDCのHuffmanのbit数を取得する
                // 最低2bit
                int getDCHuffmanSize(int huffmanValue)
                {
                    int size = getBitLengthNum(huffmanValue);
                    return size < 2 ? 2: size;
                }
            #endif

            float codeHuffman(bool isX, float2 pixel)
            {
                #ifdef _TARGET_TYPE_YA
                    // YのDCのhuffmanの値を求める
                    // 0の場合2桁、それ以外は最低3桁
                    int DC_HUFFMAN_TABLE[] = 
                    {
                        0,      // 0b00
                        2,      // 0b010
                        3,      // 0b011
                        4,      // 0b100
                        5,      // 0b101
                        6,      // 0b110
                        14,     // 0b1110
                        30,     // 0b11110
                        62,     // 0b111110
                        126,    // 0b1111110
                        254,    // 0b11111110
                        510,    // 0b111111110
                    };

                    // YのACのhuffmanの値を求める
                    // x:ZeroNum y:Category
                    // 0と1だった場合、2桁とする
                    int AC_HUFFMAN_TABLE[] = 
                    {
                        10,0,1,4,11,26,120,248,1014,65410,65411,
                        65535,12,27,121,502,2038,65412,65413,65414,65415,65416,
                        65535,28,249,1015,4084,65417,65418,65419,65420,65421,65422,
                        65535,58,503,4085,65423,65424,65425,65426,65427,65428,65429,
                        65535,59,1016,65430,65431,65432,65433,65434,65435,65436,65437,
                        65535,122,2039,65438,65439,65440,65441,65442,65443,65444,65445,
                        65535,123,4086,65446,65447,65448,65449,65450,65451,65452,65453,
                        65535,250,4087,65454,65455,65456,65457,65458,65459,65460,65461,
                        65535,504,32704,65462,65463,65464,65465,65466,65467,65468,65469,
                        65535,505,65470,65471,65472,65473,65474,65475,65476,65477,65478,
                        65535,506,65479,65480,65481,65482,65483,65484,65485,65486,65487,
                        65535,1017,65488,65489,65490,65491,65492,65493,65494,65495,65496,
                        65535,1018,65497,65498,65499,65500,65501,65502,65503,65504,65505,
                        65535,2040,65506,65507,65508,65509,65510,65511,65512,65513,65514,
                        65535,65515,65516,65517,65518,65519,65520,65521,65522,65523,65524,
                        2041,65525,65526,65527,65528,65529,65530,65531,65532,65533,65534

                        /*
                        0b1010            ,0b00              ,0b01              ,0b100             ,0b1011            ,0b11010           ,0b1111000         ,0b11111000        ,0b1111110110      ,0b1111111110000010,0b1111111110000011,
                        0b1111111111111111,0b1100            ,0b11011           ,0b1111001         ,0b111110110       ,0b11111110110     ,0b1111111110000100,0b1111111110000101,0b1111111110000110,0b1111111110000111,0b1111111110001000,
                        0b1111111111111111,0b11100           ,0b11111001        ,0b1111110111      ,0b111111110100    ,0b1111111110001001,0b1111111110001010,0b1111111110001011,0b1111111110001100,0b1111111110001101,0b1111111110001110,
                        0b1111111111111111,0b111010          ,0b111110111       ,0b111111110101    ,0b1111111110001111,0b1111111110010000,0b1111111110010001,0b1111111110010010,0b1111111110010011,0b1111111110010100,0b1111111110010101,
                        0b1111111111111111,0b111011          ,0b1111111000      ,0b1111111110010110,0b1111111110010111,0b1111111110011000,0b1111111110011001,0b1111111110011010,0b1111111110011011,0b1111111110011100,0b1111111110011101,
                        0b1111111111111111,0b1111010         ,0b11111110111     ,0b1111111110011110,0b1111111110011111,0b1111111110100000,0b1111111110100001,0b1111111110100010,0b1111111110100011,0b1111111110100100,0b1111111110100101,
                        0b1111111111111111,0b1111011         ,0b111111110110    ,0b1111111110100110,0b1111111110100111,0b1111111110101000,0b1111111110101001,0b1111111110101010,0b1111111110101011,0b1111111110101100,0b1111111110101101,
                        0b1111111111111111,0b11111010        ,0b111111110111    ,0b1111111110101110,0b1111111110101111,0b1111111110110000,0b1111111110110001,0b1111111110110010,0b1111111110110011,0b1111111110110100,0b1111111110110101,
                        0b1111111111111111,0b111111000       ,0b111111111000000 ,0b1111111110110110,0b1111111110110111,0b1111111110111000,0b1111111110111001,0b1111111110111010,0b1111111110111011,0b1111111110111100,0b1111111110111101,
                        0b1111111111111111,0b111111001       ,0b1111111110111110,0b1111111110111111,0b1111111111000000,0b1111111111000001,0b1111111111000010,0b1111111111000011,0b1111111111000100,0b1111111111000101,0b1111111111000110,
                        0b1111111111111111,0b111111010       ,0b1111111111000111,0b1111111111001000,0b1111111111001001,0b1111111111001010,0b1111111111001011,0b1111111111001100,0b1111111111001101,0b1111111111001110,0b1111111111001111,
                        0b1111111111111111,0b1111111001      ,0b1111111111010000,0b1111111111010001,0b1111111111010010,0b1111111111010011,0b1111111111010100,0b1111111111010101,0b1111111111010110,0b1111111111010111,0b1111111111011000,
                        0b1111111111111111,0b1111111010      ,0b1111111111011001,0b1111111111011010,0b1111111111011011,0b1111111111011100,0b1111111111011101,0b1111111111011110,0b1111111111011111,0b1111111111100000,0b1111111111100001,
                        0b1111111111111111,0b11111111000     ,0b1111111111100010,0b1111111111100011,0b1111111111100100,0b1111111111100101,0b1111111111100110,0b1111111111100111,0b1111111111101000,0b1111111111101001,0b1111111111101010,
                        0b1111111111111111,0b1111111111101011,0b1111111111101100,0b1111111111101101,0b1111111111101110,0b1111111111101111,0b1111111111110000,0b1111111111110001,0b1111111111110010,0b1111111111110011,0b1111111111110100,
                        0b11111111001     ,0b1111111111110101,0b1111111111110110,0b1111111111110111,0b1111111111111000,0b1111111111111001,0b1111111111111010,0b1111111111111011,0b1111111111111100,0b1111111111111101,0b1111111111111110
                        */
                    };
                #else
                                
                    // CのDCのhuffmanの値を求める
                    // 最低2桁
                    int DC_HUFFMAN_TABLE[] = 
                    {
                        0,      // 0b00
                        1,      // 0b01
                        2,      // 0b10
                        6,      // 0b110
                        14,     // 0b1110
                        30,     // 0b11110
                        62,     // 0b111110
                        126,    // 0b1111110
                        254,    // 0b11111110
                        510,    // 0b111111110
                        1022,   // 0b1111111110
                        2046,   // 0b11111111110
                    };
                    // CのACのhuffmanの値を求める
                    // x:ZeroNum y:Category
                    // 0と1だった場合、2桁とする
                    int AC_HUFFMAN_TABLE[] = 
                    {
                        0,1,4,10,24,25,56,120,500,1014,4084,
                        65535,11,57,246,501,2038,4085,65416,65417,65418,65419,
                        65535,26,247,1015,4086,32706,65420,65421,65422,65423,65424,
                        65535,27,248,1016,4087,65425,65426,65427,65428,65429,65430,
                        65535,58,502,65431,65432,65433,65434,65435,65436,65437,65438,
                        65535,59,1017,65439,65440,65441,65442,65443,65444,65445,65446,
                        65535,121,2039,65447,65448,65449,65450,65451,65452,65453,65454,
                        65535,122,2040,65455,65456,65457,65458,65459,65460,65461,65462,
                        65535,249,65463,65464,65465,65466,65467,65468,65469,65470,65471,
                        65535,503,65472,65473,65474,65475,65476,65477,65478,65479,65480,
                        65535,504,65481,65482,65483,65484,65485,65486,65487,65488,65489,
                        65535,505,65490,65491,65492,65493,65494,65495,65496,65497,65498,
                        65535,506,65499,65500,65501,65502,65503,65504,65505,65506,65507,
                        65535,2041,65508,65509,65510,65511,65512,65513,65514,65515,65516,
                        65535,16352,65517,65518,65519,65520,65521,65522,65523,65524,65525,
                        1018,32707,65526,65527,65528,65529,65530,65531,65532,65533,65534
                        /*
                        0b00              ,0b01             ,0b100             ,0b1010            ,0b11000           ,0b11001           ,0b111000          ,0b1111000         ,0b111110100       ,0b1111110110      ,0b111111110100
                        0b1111111111111111,0b1011           ,0b111001          ,0b11110110        ,0b111110101       ,0b11111110110     ,0b111111110101    ,0b1111111110001000,0b1111111110001001,0b1111111110001010,0b1111111110001011,
                        0b1111111111111111,0b11010          ,0b11110111        ,0b1111110111      ,0b111111110110    ,0b111111111000010 ,0b1111111110001100,0b1111111110001101,0b1111111110001110,0b1111111110001111,0b1111111110010000,
                        0b1111111111111111,0b11011          ,0b11111000        ,0b1111111000      ,0b111111110111    ,0b1111111110010001,0b1111111110010010,0b1111111110010011,0b1111111110010100,0b1111111110010101,0b1111111110010110,
                        0b1111111111111111,0b111010         ,0b111110110       ,0b1111111110010111,0b1111111110011000,0b1111111110011001,0b1111111110011010,0b1111111110011011,0b1111111110011100,0b1111111110011101,0b1111111110011110,
                        0b1111111111111111,0b111011         ,0b1111111001      ,0b1111111110011111,0b1111111110100000,0b1111111110100001,0b1111111110100010,0b1111111110100011,0b1111111110100100,0b1111111110100101,0b1111111110100110,
                        0b1111111111111111,0b1111001        ,0b11111110111     ,0b1111111110100111,0b1111111110101000,0b1111111110101001,0b1111111110101010,0b1111111110101011,0b1111111110101100,0b1111111110101101,0b1111111110101110,
                        0b1111111111111111,0b1111010        ,0b11111111000     ,0b1111111110101111,0b1111111110110000,0b1111111110110001,0b1111111110110010,0b1111111110110011,0b1111111110110100,0b1111111110110101,0b1111111110110110,
                        0b1111111111111111,0b11111001       ,0b1111111110110111,0b1111111110111000,0b1111111110111001,0b1111111110111010,0b1111111110111011,0b1111111110111100,0b1111111110111101,0b1111111110111110,0b1111111110111111,
                        0b1111111111111111,0b111110111      ,0b1111111111000000,0b1111111111000001,0b1111111111000010,0b1111111111000011,0b1111111111000100,0b1111111111000101,0b1111111111000110,0b1111111111000111,0b1111111111001000,
                        0b1111111111111111,0b111111000      ,0b1111111111001001,0b1111111111001010,0b1111111111001011,0b1111111111001100,0b1111111111001101,0b1111111111001110,0b1111111111001111,0b1111111111010000,0b1111111111010001,
                        0b1111111111111111,0b111111001      ,0b1111111111010010,0b1111111111010011,0b1111111111010100,0b1111111111010101,0b1111111111010110,0b1111111111010111,0b1111111111011000,0b1111111111011001,0b1111111111011010,
                        0b1111111111111111,0b111111010      ,0b1111111111011011,0b1111111111011100,0b1111111111011101,0b1111111111011110,0b1111111111011111,0b1111111111100000,0b1111111111100001,0b1111111111100010,0b1111111111100011,
                        0b1111111111111111,0b11111111001    ,0b1111111111100100,0b1111111111100101,0b1111111111100110,0b1111111111100111,0b1111111111101000,0b1111111111101001,0b1111111111101010,0b1111111111101011,0b1111111111101100,
                        0b1111111111111111,0b11111111100000 ,0b1111111111101101,0b1111111111101110,0b1111111111101111,0b1111111111110000,0b1111111111110001,0b1111111111110010,0b1111111111110011,0b1111111111110100,0b1111111111110101,
                        0b1111111010      ,0b111111111000011,0b1111111111110110,0b1111111111110111,0b1111111111111000,0b1111111111111001,0b1111111111111010,0b1111111111111011,0b1111111111111100,0b1111111111111101,0b1111111111111110
                        */
                    };

                #endif

                int zeroCount = 0;
                int outBits = 0;
                int nowBit = 0; // 現在の元データのbit位置
                float indexNum = formatedSize().x * formatedSize().y;
                float index = pixel.x + pixel.y * formatedSize().x; // 何番目のピクセルか
                int targetByte = index;
                bool isFinish = false;
                [loop]
                for(int i = 0; i < indexNum; i++)
                {
                    int nowIndex = i;
                    float2 targetUV = pixel2uv(index2pixel(nowIndex, formatedSize().x));
                    int targetIndexInBlock = index2pixel(nowIndex, (BLOCK_SIZE * BLOCK_SIZE)).x; // ブロックの中で何ピクセル目か
                    float2 value = tex2Dlod(_SelfTexture2D, float4(targetUV, 0, 0));
                    
                    int inputValue;
                    if(isX)
                    {
                        inputValue = (int)value.x;
                    }
                    else
                    {
                        inputValue = (int)value.y;
                    }

                    if(targetIndexInBlock == 0)
                    {
                        // DC
                        {
                            int category = getCategory(inputValue);
                            #ifdef _TARGET_TYPE_YA
                                int huffmanCode = DC_HUFFMAN_TABLE[category];
                                int huffmanCodeSize = getDCHuffmanSize(huffmanCode);
                            #else
                                int huffmanCode = DC_HUFFMAN_TABLE[category];
                                int huffmanCodeSize = getDCHuffmanSize(huffmanCode);
                            #endif
                            int additionalBit = getAdditionalBit(inputValue, category);

                            SET_OUT_BITS(huffmanCode, huffmanCodeSize)
                            SET_OUT_BITS(additionalBit, category)

                            zeroCount = 0;
                        }
                    }
                    else
                    {
                        // AC
                        {
                            if(inputValue == 0)
                            {
                                // データが0の場合
                                if(targetIndexInBlock == 63)
                                {
                                    // ブロック最後が0の場合
                                    // EOBを設定
                                    int category = EOB_CATEGORY;
                                    #ifdef _TARGET_TYPE_YA
                                        int huffmanCode = AC_HUFFMAN_TABLE[EOB_ZERONUM * 11 + category];
                                    #else
                                        int huffmanCode = AC_HUFFMAN_TABLE[EOB_ZERONUM * 11 + category];
                                    #endif
                                    int huffmanCodeSize = getACHuffmanSize(huffmanCode);
                                    int additionalBit = 0;

                                    SET_OUT_BITS(huffmanCode, huffmanCodeSize)

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
                                for(int i = 0; i < 4; i++)
                                {
                                    if(zeroCount < 16)
                                    {
                                        break;
                                    }
                                    // 累積した0が16以上ある場合、16を切るまでZRLを設定
                                    int category = ZRL_CATEGORY;
                                    #ifdef _TARGET_TYPE_YA
                                        int huffmanCode = AC_HUFFMAN_TABLE[ZRL_ZERONUM * 11 + category];
                                    #else
                                        int huffmanCode = AC_HUFFMAN_TABLE[ZRL_ZERONUM * 11 + category];
                                    #endif
                                    int huffmanCodeSize = getACHuffmanSize(huffmanCode);
                                    int additionalBit = 0;

                                    SET_OUT_BITS(huffmanCode, huffmanCodeSize)

                                    zeroCount -= 16;
                                }
                                if(isFinish)
                                {
                                    break;
                                }
                                {
                                    int category = getCategory(inputValue);
                                    #ifdef _TARGET_TYPE_YA
                                        int huffmanCode = AC_HUFFMAN_TABLE[zeroCount * 11 + category];
                                    #else
                                        int huffmanCode = AC_HUFFMAN_TABLE[zeroCount * 11 + category];
                                    #endif
                                    int huffmanCodeSize = getACHuffmanSize(huffmanCode);
                                    int additionalBit = getAdditionalBit(inputValue, category);

                                    SET_OUT_BITS(huffmanCode, huffmanCodeSize)
                                    SET_OUT_BITS(additionalBit, category)

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
                return outBits / 255.0;
            }
            
            float2 frag(v2f_customrendertexture IN) : COLOR
            {
                // intは20bitくらいまでしか使えない

                float2 output = 0;
                float2 pixel = uv2pixel(IN.localTexcoord.xy);

                output.x = codeHuffman(true, pixel);
                output.y = codeHuffman(false, pixel);
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
                        float2 checkValue = tex2Dlod(_SelfTexture2D, float4(pixel2uv(index2pixel(i, formatedSize().x)), 0, 0));
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
                        float4 checkValue = tex2Dlod(_SelfTexture2D, float4(pixel2uv(index2pixel(i, formatedSize().x)), 0, 0));
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