
using UdonSharp;
using UnityEngine;
using VRC.SDKBase;
using VRC.Udon;

namespace HDAssets.ImageSync
{
    [UdonBehaviourSyncMode(BehaviourSyncMode.Continuous)]
    public class CaptureCamera : UdonSharpBehaviour
    {
        private Camera cam;
        [SerializeField]private DataImageCapture dataImageCapture;
        void Start()
        {
            cam = GetComponent<Camera>();
            cam.enabled = false;
        }
        public override void OnPickupUseDown()
        {
            if(cam.enabled)
            {
                cam.enabled = false;
                dataImageCapture.RequestSend();
            }
            else
            {
                cam.enabled = true;
            }
        }

        public override void OnDrop()
        {
            cam.enabled = false;
        }
        public override void OnPickup()
        {
            dataImageCapture.RequestOwner();
            cam.enabled = true;
        }
        #if UNITY_EDITOR
        public override void Interact()
        {
            OnPickupUseDown();
        }
        #endif

    }
}
