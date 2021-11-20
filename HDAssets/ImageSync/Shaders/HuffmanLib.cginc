
// 元の値からビットの長さを取得する
int getBitLengthNum(int value)
{
    int absValue = (int)abs(value);
    if(absValue == 0)
    {
        return 0;
    }
    else
    {
        float powValue = log2(absValue);
        powValue = max(0, powValue);
        return (int)powValue + 1;
    }
}

// 元の値からカテゴリを取得する
// もとの値がnbitのとき、カテゴリはn、付加ビットもn（nbit目は＋であれば1である）
int getCategory(int value)
{
    if(value == 0)
    {
        return 0;
    }
    else
    {
        return getBitLengthNum(value);
    }
}

// 値から追加bitを求める
// 追加bitはcategory - 1 bit(0の場合はなし)のbit数
int getAdditionalBit(int value, int category)
{
    int additionalBit;
    if(value == 0)
    {
        additionalBit = 0;
    }
    else if(value > 0)
    {
        // 各カテゴリの小さい値を0とする
        additionalBit = value;
    }
    else
    {
        // 各カテゴリの小さい値を0とする
        additionalBit = (int)(pow(2, category) - 1) + value;
    }
    return additionalBit;
}

// 追加bitから値を求める
int fromAdditionalBit(int additionalBit, int category)
{
    int value;
    if(category == 0)
    {
        value = 0;
    }
    else if(floor(additionalBit / pow(2, category - 1)) == 1)
    {
        // 正の値
        value = additionalBit;
    }
    else
    {
        // 負の値
        value = (int)(additionalBit - (int)(pow(2, category) - 1));
    }
    return value;
}




// ACのHuffmanのbit数を取得する
// 最低2bit
int getACHuffmanSize(int huffmanValue)
{
    int size = getBitLengthNum(huffmanValue);
    return size < 2 ? 2: size;
}

#define EOB_ZERONUM  ((int)0x0)
#define EOB_CATEGORY ((int)0x0)
#define ZRL_ZERONUM  ((int)0xF)
#define ZRL_CATEGORY ((int)0x0)

#define SET_OUT_BITS(value, length) {\
    if(targetByte * 8 < nowBit + length)\
    {\
        if((targetByte + 1) * 8 <= nowBit + length)\
        {\
            int useBitLength = (targetByte + 1) * 8 - nowBit;\
            isFinish = true;\
            outBits = outBits << useBitLength;\
            outBits = outBits | ((value >> (length - useBitLength)) & 0xFF);\
        }\
        else\
        {\
            int useBitLength = (nowBit + length) - targetByte * 8;\
            int shiftBit = useBitLength;\
            if(length < shiftBit)\
            {\
                shiftBit = length;\
            }\
            outBits = outBits << shiftBit;\
            outBits = outBits | (value & ((1 << useBitLength) - 1));\
        }\
    }\
    nowBit += length;\
    if(isFinish)\
    {\
        break;\
    }\
}

// 1bit目の場合、新たにピクセルからデータを持ってくる
#define GET_BIT_DATA(inoutValue) {\
    int targetBitInByte = (nowBit & 7);\
    if(targetBitInByte == 0)\
    {\
        float2 targetUV = pixel2uv(index2pixel((nowBit >> 3), formatedSize().x));\
        if(isX)\
        {\
            nowPixelValue = round(tex2Dlod(_SelfTexture2D, float4(targetUV, 0, 0)).x * 255);\
        }\
        else\
        {\
            nowPixelValue = round(tex2Dlod(_SelfTexture2D, float4(targetUV, 0, 0)).y * 255);\
        }\
    }\
    inoutValue = (inoutValue << 1) | getTargetBitData(targetBitInByte, nowPixelValue);\
    nowBit++;\
}
