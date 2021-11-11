
using UdonSharp;
using UnityEngine;
using VRC.SDKBase;
using VRC.Udon;

namespace HDAssets.ImageSync
{
    [UdonBehaviourSyncMode(BehaviourSyncMode.Continuous)]
    public class CaptureCamera : UdonSharpBehaviour
    {
        [SerializeField]private DataImageCapture dataImageCapture;
        void Start()
        {
            
        }
        public override void OnPickupUseDown()
        {
            dataImageCapture.RequestCapture();
        }
        #if UNITY_EDITOR
        public override void Interact()
        {
            OnPickupUseDown();
        }
        #endif

        public override void OnPickup()
        {
            dataImageCapture.RequestOwner();
        }
    }
}
