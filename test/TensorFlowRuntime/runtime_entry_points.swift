// RUN: %target-run-simple-swift
// REQUIRES: executable_test
// REQUIRES: swift_test_mode_optimize

import CTensorFlow
import TensorFlow
import TensorFlowUnittest
import StdlibUnittest

var RuntimeEntryPointTests = TestSuite("RuntimeEntryPoint")

RuntimeEntryPointTests.testCPUOrGPU("RoundTrip_CTensorHandle_AnyTensorHandle") {
  let zero: TensorHandle<Float> =
    #tfop("Const", dtype: Float.self, value$tensor: 0.0)
  var cHandle = _TFCGetCTensorHandleFromSwift(zero as _AnyTensorHandle)
  let status = TF_NewStatus()
  // We must do a copy, i.e. a retain on the tensor handle, to make sure it won't
  // get double-free'd when both `zero` and `anyHandle` below go out of scope.
  cHandle = TFE_TensorHandleCopySharingTensor(cHandle, status)
  expectEqual(TF_GetCode(status), TF_OK)
  TF_DeleteStatus(status)
  let anyHandle = _TFCCreateTensorHandleFromC(cHandle)
  let tensor = Tensor(handle: anyHandle as! TensorHandle<Float>)
  print(tensor)
  expectTrue(tensor == Tensor(0.0))
}

runAllTests()
