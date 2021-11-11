#define QUALITY 2 // 12 くらいまで

#define COLOR_SAMPLE 2 // 変更不可

#define PI 3.141592

#define BLOCK_SIZE 8 // 変更不可
#define SEPARATE_DC_BLOCK 16 // 変更不可

// RGB to YCbCr
float3 rgb2ycbcr(float3 rgb)
{
    return float3 // (0-255)
    (
        0   +   (0.299      *   rgb.x)  +   (0.587      *   rgb.y)  +   (0.114      *   rgb.z),
        128 -   (0.168736   *   rgb.x)  -   (0.331264   *   rgb.y)  +   (0.5        *   rgb.z),
        128 +   (0.5        *   rgb.x)  -   (0.418688   *   rgb.y)  -   (0.081312   *   rgb.z)
    );
}

// YCbCr to RGB
float3 ycbcr2rgb(float3 ycbcr)
{
    return float3 // (0-255)
    (
        ycbcr.x                                     +   1.402       *   (ycbcr.z - 128),
        ycbcr.x     - 0.344136  *   (ycbcr.y - 128) -   0.714136    *   (ycbcr.z - 128),
        ycbcr.x     + 1.772     *   (ycbcr.y - 128)
    );
}

float phi(float k, float i, float N)
{
    if(k == 0)
    {
        return 1 / sqrt(N);
    }
    else
    {
        return sqrt(2/N) * cos(((2 * i + 1) * k * PI) / (2 * N));
    }
}

float2 formatedSize()
{
    return float2(_CustomRenderTextureWidth, _CustomRenderTextureHeight);
}

// xMaxで区切ったx,y
float2 index2pixel(float index, float xMax)
{
    return float2(round(fmod(index, xMax)), floor((index + 0.1) / xMax));
}

// pixelを0-1に変換
float2 pixel2uv(float2 pixel)
{
    float2 offsetPixel = round(pixel);
    offsetPixel += float2(0.1, 0.1); // uvをそれぞれ0.5px分ずつずらす
    return offsetPixel / formatedSize();
}

// uvをpixelに変換
float2 uv2pixel(float2 uv)
{
    float2 offsetPixel = uv * formatedSize();
    offsetPixel -= float2(0.1, 0.1);
    return round(offsetPixel);
}

// 量子化テーブル（Y/A）
float quantizeValueY(float2 pixel, float quality)
{
    int quantizeTableY[] =
    {
        16, 11, 10, 16, 24, 40, 51, 61,
        12, 12, 14, 19, 26, 58, 60, 55,
        14, 13, 16, 24, 40, 57, 69, 56,
        14, 17, 22, 29, 51, 87, 80, 62,
        18, 22, 37, 56, 68,109,103, 77,
        24, 35, 55, 64, 81,104,113, 92,
        49, 64, 78, 87,103,121,120,101,
        72, 92, 95, 98,112,100,103, 99
    };
    return quantizeTableY[round(pixel.x) + round(pixel.y) * BLOCK_SIZE] / quality;
}

// 量子化テーブル（C）
float quantizeValueC(float2 pixel, float quality)
{
    int quantizeTableC[] = 
    {
        17, 18, 24, 47, 99, 99, 99, 99,
        18, 21, 26, 66, 99, 99, 99, 99,
        24, 26, 56, 99, 99, 99, 99, 99,
        47, 66, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99
    };
    return quantizeTableC[round(pixel.x) + round(pixel.y) * BLOCK_SIZE] / quality;
}

// ジグザグに走査するためのテーブル
float2 serializePosition(int index)
{
    float2 serializePositionTable[] =
    {
        float2(0, 0), float2(1, 0), float2(0, 1), float2(0, 2), float2(1, 1), float2(2, 0), float2(3, 0), float2(2, 1),
        float2(1, 2), float2(0, 3), float2(0, 4), float2(1, 3), float2(2, 2), float2(3, 1), float2(4, 0), float2(5, 0),
        float2(4, 1), float2(3, 2), float2(2, 3), float2(1, 4), float2(0, 5), float2(0, 6), float2(1, 5), float2(2, 4),
        float2(3, 3), float2(4, 2), float2(5, 1), float2(6, 0), float2(7, 0), float2(6, 1), float2(5, 2), float2(4, 3),
        float2(3, 4), float2(2, 5), float2(1, 6), float2(0, 7), float2(1, 7), float2(2, 6), float2(3, 5), float2(4, 4),
        float2(5, 3), float2(6, 2), float2(7, 1), float2(7, 2), float2(6, 3), float2(5, 4), float2(4, 5), float2(3, 6),
        float2(2, 7), float2(3, 7), float2(4, 6), float2(5, 5), float2(6, 4), float2(7, 3), float2(7, 4), float2(6, 5),
        float2(5, 6), float2(4, 7), float2(5, 7), float2(6, 6), float2(7, 5), float2(7, 6), float2(6, 7), float2(7, 7)
    };
    return serializePositionTable[index];
}

// ジグザグに走査したものを戻すためのテーブル
int deSerializeIndex(float2 position)
{
    int deserializeIndexTable[] =
    {
        0,  1,  5,  6,  14, 15, 27, 28,
        2,  4,  7,  13, 16, 26, 29, 42,
        3,  8,  12, 17, 25, 30, 41, 43,
        9,  11, 18, 24, 31, 40, 44, 53,
        10, 19, 23, 32, 39, 45, 52, 54,
        20, 22, 33, 38, 46, 51, 55, 60,
        21, 34, 37, 47, 50, 56, 59, 61,
        35, 36, 48, 49, 57, 58, 62, 63
    };
    return deserializeIndexTable[round(position.x + position.y * BLOCK_SIZE)];
}
