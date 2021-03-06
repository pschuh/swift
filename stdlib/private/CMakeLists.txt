if(SWIFT_BUILD_STDLIB OR SWIFT_BUILD_SDK_OVERLAY)
  add_subdirectory(SwiftPrivate)
endif()

if(SWIFT_BUILD_SDK_OVERLAY)
  # SwiftPrivatePthreadExtras makes use of Darwin/Glibc, which is part of the
  # SDK overlay. It can't be built separately from the SDK overlay.
  add_subdirectory(StdlibUnittest)
  add_subdirectory(StdlibUnicodeUnittest)
  add_subdirectory(StdlibCollectionUnittest)
  add_subdirectory(SwiftPrivateLibcExtras)
  add_subdirectory(SwiftPrivatePthreadExtras)

  # SWIFT_ENABLE_TENSORFLOW
  if(SWIFT_ENABLE_TENSORFLOW)
    add_subdirectory(TensorFlowUnittest)
  endif()

  if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    add_subdirectory(StdlibUnittestFoundationExtras)
    if (SWIFT_INCLUDE_TESTS)
      add_subdirectory(SwiftReflectionTest)
    endif()
  endif()
endif()
