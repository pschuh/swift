// RUN: %target-swift-frontend -emit-sil %s -verify

// This file contains tests that used to be in ./crashers.swift that produced
// expected errors in the deabstraction pass, which prevented partitioning from
// running.
//
// Once we move partitioning into the mandatory pipeline, we should be able to
// move these tests back into ./crashers.swift.

import TensorFlow

// b/75247714: #tfop crashes when attribute argument is a tuple
public func test75247714() {
  // expected-error @+1 {{attribute 'bar' cannot be an enum, struct, or tuple}}
  let _ : () = #tfop("foo", bar: (1, 2))
}


// b/76115311
func genericMethod76115311<Scalar : Numeric>(with value: Scalar = 0) -> Tensor<Scalar> {
  return #tfop("FooOp", value)
}

public func b76115311() {
  // expected-error @+1 {{argument of type 'Builtin.FPIEEE32' is not a TensorFlow value or an aggregate of TensorFlow values}}
  let matrix: Tensor<Float> = genericMethod76115311()
  _ = matrix+matrix
}
