
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
        [SerializeField] private Texture2D targetTexYA;
        [SerializeField] private Texture2D targetTexC;
        [SerializeField] private CustomRenderTexture crtYAImageCompress;
        [SerializeField] private CustomRenderTexture crtCImageCompress;
        [SerializeField] private CustomRenderTexture crtYAImageDecompress;
        [SerializeField] private CustomRenderTexture crtCImageDecompress;
        [SerializeField] private CustomRenderTexture crtImageDecompress;
        [SerializeField] private Texture2D yaDataOutTex;
        [SerializeField] private Texture2D cDataOutTex;
        private Camera cam;

        [UdonSynced(UdonSyncMode.None)] private Color32[] yaSyncValues = new Color32[0];

        [UdonSynced(UdonSyncMode.None)] private Color32[] cSyncValues = new Color32[0];
        [SerializeField] [UdonSynced(UdonSyncMode.None)] private short syncIndex = -255;

        [SerializeField] private short beforeSyncIndex = -255;
        [SerializeField] private TextMeshPro sendSizeText;

        public void RequestOwner()
        {
            if(!Networking.IsOwner(Networking.LocalPlayer, gameObject))
            {
                Networking.SetOwner(Networking.LocalPlayer, gameObject);
            }
        }
        void Start()
        {
            cam = GetComponent<Camera>();
            cam.enabled = false;
        }

        void OnPostRender()
        {
            // YA
            // C
            // のかたちで縦に並んでいる
            // 左上が原点
            Rect rectYA = new Rect(
                0,
                0,
                cam.pixelRect.width,
                Mathf.RoundToInt(cam.pixelRect.height / 2)
            );
            Rect rectC = new Rect(
                0,
                Mathf.RoundToInt(cam.pixelRect.height / 2),
                Mathf.RoundToInt(cam.pixelRect.width  / 2),
                Mathf.RoundToInt(cam.pixelRect.height / 4)
            );
            targetTexYA.ReadPixels(rectYA, 0, 0, false);
            targetTexYA.Apply(false);
            targetTexC.ReadPixels(rectC, 0, 0, false);
            targetTexC.Apply(false);
            cam.enabled = false;
            StartSend();
        }
        public void RequestCapture()
        {
            crtYAImageCompress.Update(1);
            crtCImageCompress.Update(1);

            SendCustomEventDelayedFrames("SendCrtUpdate", 1);
        }
        private void StartSend()
        {
            syncIndex--;
            if(syncIndex < 0)
            {
                syncIndex = 2047;
            }
            Color32[] yaData = targetTexYA.GetPixels32();
            Color32[] cData = targetTexC.GetPixels32();
            
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
            yaSyncValues = new Color32[yaDataSize + 1]; // size格納Pixel分を追加
            cSyncValues = new Color32[cDataSize + 1]; // size格納Pixel分を追加
            Array.Copy(yaData, yaSyncValues, yaSyncValues.Length);
            Array.Copy(cData, cSyncValues, cSyncValues.Length);
            
            RequestSerialization();
            #if UNITY_EDITOR
            OnDeserialization();
            #endif
        }
        public void SendCrtUpdate()
        {
            cam.enabled = true;
        }

        private void StartGet()
        {
            Color32[] yaOutData = yaDataOutTex.GetPixels32();
            Color32[] cOutData = cDataOutTex.GetPixels32();
            Array.Clear(yaOutData, 0, yaOutData.Length);
            Array.Clear(cOutData, 0, cOutData.Length);
            
            Array.Copy(yaSyncValues, yaOutData, yaSyncValues.Length);
            Array.Copy(cSyncValues, cOutData, cSyncValues.Length);

            yaDataOutTex.SetPixels32(yaOutData, 0);
            yaDataOutTex.Apply(false);
            cDataOutTex.SetPixels32(cOutData, 0);
            cDataOutTex.Apply(false);
            crtYAImageDecompress.Update(1);
            crtCImageDecompress.Update(1);

            SendCustomEventDelayedFrames("ResCrtUpdate", 100);
        }
        public void ResCrtUpdate()
        {
            crtImageDecompress.Update(2);
        }

        override public void OnDeserialization()
        {
            // 値が更新されている.
            if(beforeSyncIndex != syncIndex)
            {
                StartGet();
            }
            beforeSyncIndex = syncIndex;
        }

        override public void OnPostSerialization(VRC.Udon.Common.SerializationResult result)
        {
            if(!result.success)
            {
                Debug.LogError("送信に失敗しました");
                return;
            }
            Debug.Log("SendByteSize:" + result.byteCount + "byte");
            if(sendSizeText != null)
            {
                sendSizeText.text = "SendByteSize:" + result.byteCount + "byte";
            }


            OnDeserialization();
        }
    }
}