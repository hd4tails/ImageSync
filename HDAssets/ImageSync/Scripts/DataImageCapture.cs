
using UdonSharp;
using UnityEngine;
using VRC.SDKBase;
using VRC.Udon;
using System;
using TMPro;

namespace HDAssets.ImageSync
{
    [UdonBehaviourSyncMode(BehaviourSyncMode.Manual)]
    public class DataImageCapture : UdonSharpBehaviour
    {
        #region Inspector
        [HeaderAttribute("=================送信元で更新するか=================")]
        [SerializeField] private bool isUpdateSend = true;
        [HeaderAttribute("=================入力/出力画像=================")]
        [HeaderAttribute("512px角-RGBA32の入力画像")]
        [SerializeField] private Texture inputImage;
        [HeaderAttribute("512px角-RGBA32の出力画像(CustomRenderTexture)")]
        [SerializeField] private CustomRenderTexture outputImage;

        [HeaderAttribute("=================その他=================")]
        [HeaderAttribute("送信サイズ表示用のTMP")]
        [SerializeField] private TextMeshPro sentSizeText;

        [HeaderAttribute("=================送信/受信=================")]
        [HeaderAttribute("Udonで操作するため、圧縮済みの画像(Y/A)を一時的に格納するテクスチャ")]
        [SerializeField] private Texture2D temporaryImageYA;
        [HeaderAttribute("Udonで操作するため、圧縮済みの画像(CbCr)を一時的に格納するテクスチャ")]
        [SerializeField] private Texture2D temporaryImageCbCr;

        [HeaderAttribute("=================圧縮/展開=================")]
        [HeaderAttribute("画像の圧縮処理を行うCustomRenderTexture(Y/A)")]
        [SerializeField] private CustomRenderTexture imageCompressCRTYA;
        [HeaderAttribute("画像の圧縮処理を行うCustomRenderTexture(CbCr)")]
        [SerializeField] private CustomRenderTexture imageCompressCRTCbCr;
        [HeaderAttribute("画像の展開処理を行うCustomRenderTexture(Y/A)")]
        [SerializeField] private CustomRenderTexture imageDecompressCRTYA;
        [HeaderAttribute("画像の展開処理を行うCustomRenderTexture(CbCr)")]
        [SerializeField] private CustomRenderTexture imageDecompressCRTCbCr;
        #endregion
        // Inspector

        #region Sync
        // 同期するデータ(Y/A)
        [UdonSynced(UdonSyncMode.None)] private Color32[] syncValuesYA = new Color32[0];
        // 同期するデータ(CbCr)
        [UdonSynced(UdonSyncMode.None)] private Color32[] syncValuesCbCr = new Color32[0];
        // 同期されたデータの番号
        [UdonSynced(UdonSyncMode.None)] private short syncIndex = -255;
        #endregion
        // Sync

        #region Valiable
        // Udonで操作するため、圧縮済みの画像を取り込むカメラ
        private Camera dataCaptureCamera;
        // 1つ前に同期されたデータの番号
        private short beforeSyncIndex = -255;
        #endregion
        // Valiable

        /*
         * オーナーを取得する
         * 送信前にオーナーを取得しておくこと
         */
        public void RequestOwner()
        {
            if(!Networking.IsOwner(Networking.LocalPlayer, gameObject))
            {
                Networking.SetOwner(Networking.LocalPlayer, gameObject);
            }
        }
        /*
         * 送信を要求する
         */
        public void RequestSend()
        {
            #if UNITY_EDITOR
            // オーナーで無い時は処理を止める
            if(!Networking.IsOwner(Networking.LocalPlayer, gameObject))
            {
                return;
            }
            #endif
            // 圧縮を行う
            imageCompressCRTYA.Update(1);
            imageCompressCRTCbCr.Update(1);
            
            // 1F待ってからデータ読み込み用のカメラをOnにする
            SendCustomEventDelayedFrames("_StartDataCapture", 1);
        }

        void Start()
        {
            dataCaptureCamera = GetComponent<Camera>();
            dataCaptureCamera.enabled = false;

            // 圧縮の入力に指定された画像を設定する
            imageCompressCRTYA.material.SetTexture("_MainTex", inputImage);
            imageCompressCRTCbCr.material.SetTexture("_MainTex", inputImage);
        }

        void OnPostRender()
        {
            // 左上が原点でY/A-CbCrの順で並べている
            Rect rectYA = new Rect(
                0,
                0,
                dataCaptureCamera.pixelRect.width,
                Mathf.RoundToInt(dataCaptureCamera.pixelRect.height / 2)
            );
            Rect rectC = new Rect(
                0,
                Mathf.RoundToInt(dataCaptureCamera.pixelRect.height / 2),
                Mathf.RoundToInt(dataCaptureCamera.pixelRect.width  / 2),
                Mathf.RoundToInt(dataCaptureCamera.pixelRect.height / 4)
            );
            // 読み込んだデータをtemporaryの画像に書き込む
            temporaryImageYA.ReadPixels(rectYA, 0, 0, false);
            temporaryImageYA.Apply(false);
            temporaryImageCbCr.ReadPixels(rectC, 0, 0, false);
            temporaryImageCbCr.Apply(false);
            // データ読み込み用のカメラを止める
            dataCaptureCamera.enabled = false;

            // 送信開始
            DoSync();
        }
        private void DoSync()
        {
            // データの番号を更新
            syncIndex--;
            if(syncIndex < 0)
            {
                syncIndex = 2047;
            }

            Color32[] yaData = temporaryImageYA.GetPixels32();
            Color32[] cData = temporaryImageCbCr.GetPixels32();
            
            int yaDataSize = yaData[0].r
                             + yaData[0].g * 0x100
                             + yaData[0].b * 0x10000
                             + yaData[0].a * 0x1000000;
            int cDataSize  = cData[0].r
                             + cData[0].g * 0x100
                             + cData[0].b * 0x10000
                             + cData[0].a * 0x1000000;
            Debug.Log("yaDataSize"+yaDataSize);
            Debug.Log("cDataSize"+cDataSize);
            if(yaDataSize < 0 || cDataSize < 0)
            {
                Debug.Log("SendDataSizeError");
                return;
            }
            syncValuesYA = new Color32[yaDataSize + 1]; // size格納Pixel分を追加
            syncValuesCbCr = new Color32[cDataSize + 1]; // size格納Pixel分を追加
            Array.Copy(yaData, syncValuesYA, syncValuesYA.Length);
            Array.Copy(cData, syncValuesCbCr, syncValuesCbCr.Length);
            
            RequestSerialization();
            #if UNITY_EDITOR
            if(isUpdateSend)
            {
                // エディタ上ではSerializationが呼ばれないため、明示的に呼ぶ
                // 送信側も更新する場合はOnDeserializationを呼ぶ
                OnDeserialization();
            }
            #endif
        }
        public void _StartDataCapture()
        {
            // データ読み込み用のカメラをつける
            dataCaptureCamera.enabled = true;
        }
        override public void OnDeserialization()
        {
            // 値が更新されている.
            if(beforeSyncIndex != syncIndex)
            {
                DoReceive();
                beforeSyncIndex = syncIndex;
            }
        }

        private void DoReceive()
        {
            Color32[] yaOutData = temporaryImageYA.GetPixels32();
            Color32[] cOutData = temporaryImageCbCr.GetPixels32();
            Array.Clear(yaOutData, 0, yaOutData.Length);
            Array.Clear(cOutData, 0, cOutData.Length);
            
            Array.Copy(syncValuesYA, yaOutData, syncValuesYA.Length);
            Array.Copy(syncValuesCbCr, cOutData, syncValuesCbCr.Length);

            temporaryImageYA.SetPixels32(yaOutData, 0);
            temporaryImageYA.Apply(false);
            temporaryImageCbCr.SetPixels32(cOutData, 0);
            temporaryImageCbCr.Apply(false);
            DoDecompress();
        }
        public void DoDecompress()
        {
            imageDecompressCRTYA.Update(1);
            imageDecompressCRTCbCr.Update(1);
            outputImage.Update(2);
        }


        override public void OnPostSerialization(VRC.Udon.Common.SerializationResult result)
        {
            if(!result.success)
            {
                Debug.LogError("送信に失敗しました");
                return;
            }
            Debug.Log("SendByteSize:" + result.byteCount + "byte");
            if(sentSizeText != null)
            {
                sentSizeText.text = "SendByteSize:" + result.byteCount + "byte";
            }

            if(isUpdateSend)
            {
                // 送信側も更新する場合はOnDeserializationを呼ぶ
                OnDeserialization();
            }
            else
            {
                beforeSyncIndex = syncIndex;
            }
        }
    }
}