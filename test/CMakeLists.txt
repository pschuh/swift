function(swift_configure_lit_site_cfg source_path destination_path installed_name)
  if (CMAKE_CFG_INTDIR STREQUAL ".")
    set(SWIFT_BUILD_MODE ".")
  else ()
    set(SWIFT_BUILD_MODE "%(build_mode)s")
  endif ()

  string(REPLACE ${CMAKE_CFG_INTDIR} ${SWIFT_BUILD_MODE} LLVM_TOOLS_DIR ${LLVM_TOOLS_BINARY_DIR})
  string(REPLACE ${CMAKE_CFG_INTDIR} ${SWIFT_BUILD_MODE} LLVM_LIBS_DIR  ${LLVM_LIBRARY_DIR})

  if (XCODE)
    string(REPLACE ${CMAKE_CFG_INTDIR} Debug LIT_SWIFTLIB_DIR ${SWIFTLIB_DIR})
  else ()
    set(LIT_SWIFTLIB_DIR ${SWIFTLIB_DIR})
  endif ()

  configure_file("${source_path}" "${destination_path}" @ONLY)

  if(NOT "${installed_name}" STREQUAL "")
    swift_install_in_component(testsuite-tools
        FILES "${destination_path}"
        RENAME "${installed_name}"
        DESTINATION "share/swift/testsuite")
  endif()
endfunction()

function(normalize_boolean_spelling var_name)
  if(${var_name})
    set("${var_name}" TRUE PARENT_SCOPE)
  else()
    set("${var_name}" FALSE PARENT_SCOPE)
  endif()
endfunction()

function(get_test_dependencies SDK result_var_name)
  set(deps)

  if(SWIFT_BUILD_STDLIB)
    list(APPEND deps SwiftUnitTests)
  endif()

  set(deps_binaries
      swift swift-ide-test swift-syntax-test sil-opt swift-llvm-opt swift-demangle
      sil-func-extractor sil-llvm-gen sil-nm sil-passpipeline-dumper
      lldb-moduleimport-test swift-reflection-dump swift-remoteast-test
      swift-api-digester swift-refactor swift-demangle-yamldump)
  if(NOT SWIFT_BUILT_STANDALONE)
    list(APPEND deps_binaries FileCheck arcmt-test c-arcmt-test c-index-test
         clang llc llvm-cov llvm-dwarfdump llvm-link llvm-as llvm-dis
         llvm-bcanalyzer llvm-nm llvm-readobj llvm-profdata count not)
  endif()
  if(SWIFT_BUILD_SOURCEKIT)
    list(APPEND deps_binaries sourcekitd-test complete-test)
  endif()

  if(("${SDK}" STREQUAL "IOS") OR
     ("${SDK}" STREQUAL "TVOS") OR
     ("${SDK}" STREQUAL "WATCHOS") OR
     ("${SDK}" STREQUAL "OSX") OR
     ("${SDK}" STREQUAL "IOS_SIMULATOR") OR
     ("${SDK}" STREQUAL "TVOS_SIMULATOR") OR
     ("${SDK}" STREQUAL "WATCHOS_SIMULATOR") OR
     ("${SDK}" STREQUAL "LINUX") OR
     ("${SDK}" STREQUAL "CYGWIN") OR
     ("${SDK}" STREQUAL "FREEBSD") OR
     ("${SDK}" STREQUAL "ANDROID") OR
     ("${SDK}" STREQUAL "WINDOWS") OR
     ("${SDK}" STREQUAL "HAIKU"))
    # No extra dependencies.
  else()
    message(FATAL_ERROR "Unknown SDK: ${SDK}")
  endif()

  if(XCODE)
    # Xcode's build paths have a configuration variable in them,
    # so CMake can't match them at compile time. Just use target names.
    list(APPEND deps ${deps_binaries})
  else()
    foreach(binary ${deps_binaries})
      list(APPEND deps "${SWIFT_NATIVE_SWIFT_TOOLS_PATH}/${binary}")
    endforeach()
  endif()

  set("${result_var_name}" "${deps}" PARENT_SCOPE)
endfunction()

if(PATH_TO_LLVM_SOURCE)
  set(LIT "${PATH_TO_LLVM_SOURCE}/utils/lit/lit.py")
else()
  set(LIT "${PATH_TO_LLVM_BUILD}/${CMAKE_CFG_INTDIR}/bin/llvm-lit")
  # Installed LLVM does not contain ${CMAKE_CFG_INTDIR} in paths.
  if(NOT EXISTS "${LIT}")
    set(LIT "${PATH_TO_LLVM_BUILD}/llvm-lit/bin")
  endif()
endif()

# Incremental mode in lit orders test files by the last modification time
# instead of by the path, which is good for CI. In this mode lit also updates
# the mtime on the failed tests, which makes them run first on the
# consecutive execution, which makes local builds fail faster.
set(SWIFT_TEST_EXTRA_ARGS "--incremental")

if(NOT SWIFT_INCLUDE_TOOLS)
  list(APPEND SWIFT_TEST_EXTRA_ARGS
       "--path=${SWIFT_NATIVE_LLVM_TOOLS_PATH}"
       "--path=${SWIFT_NATIVE_CLANG_TOOLS_PATH}"
       "--path=${SWIFT_NATIVE_SWIFT_TOOLS_PATH}")
  if(SWIFT_BUILD_STDLIB)
    list(APPEND SWIFT_TEST_EXTRA_ARGS
         "--param" "test_resource_dir=${SWIFTLIB_DIR}")
  endif()
endif()

option(SWIFT_TEST_USE_LEAKS "Run Swift stdlib tests under leaks" FALSE)
if (SWIFT_TEST_USE_LEAKS)
  list(APPEND SWIFT_TEST_EXTRA_ARGS "--param" "leaks-all")
endif()

if(NOT CMAKE_CFG_INTDIR STREQUAL ".")
  list(APPEND SWIFT_TEST_EXTRA_ARGS
       "--param" "build_mode=${CMAKE_CFG_INTDIR}")
endif()

if (LLVM_USE_SANITIZER STREQUAL "Address")
  set(SWIFT_ASAN_BUILD TRUE)
endif()

# Normalize spelling of boolean values.
normalize_boolean_spelling(LLVM_ENABLE_ASSERTIONS)
normalize_boolean_spelling(SWIFT_STDLIB_ASSERTIONS)
normalize_boolean_spelling(SWIFT_AST_VERIFIER)
normalize_boolean_spelling(SWIFT_ASAN_BUILD)
normalize_boolean_spelling(SWIFT_ENABLE_SOURCEKIT_TESTS)
# SWIFT_ENABLE_TENSORFLOW
normalize_boolean_spelling(SWIFT_ENABLE_TENSORFLOW)
normalize_boolean_spelling(SWIFT_ENABLE_TENSORFLOW_GPU)
is_build_type_optimized("${SWIFT_STDLIB_BUILD_TYPE}" SWIFT_OPTIMIZED)

set(profdata_merge_worker
    "${CMAKE_CURRENT_SOURCE_DIR}/../utils/profdata_merge/main.py")

set(TEST_MODES
    optimize_none optimize optimize_unchecked optimize_size
    only_executable only_non_executable
)
set(TEST_SUBSETS
    primary
    validation
    all
    only_validation
    only_long
    only_stress
)

if(NOT "${COVERAGE_DB}" STREQUAL "")
  add_custom_target("touch-covering-tests"
      COMMAND "${SWIFT_SOURCE_DIR}/utils/coverage/coverage-touch-tests" "--swift-dir" "${SWIFT_SOURCE_DIR}" "--coverage-db" "${COVERAGE_DB}"
      COMMENT "Touching covering tests")
endif()

foreach(SDK ${SWIFT_SDKS})
  foreach(ARCH ${SWIFT_SDK_${SDK}_ARCHITECTURES})
    # Configure variables for this subdirectory.
    set(VARIANT_SUFFIX "-${SWIFT_SDK_${SDK}_LIB_SUBDIR}-${ARCH}")
    set(VARIANT_TRIPLE "${SWIFT_SDK_${SDK}_ARCH_${ARCH}_TRIPLE}${SWIFT_SDK_${SDK}_DEPLOYMENT_VERSION}")
    set(VARIANT_SDK "${SWIFT_SDK_${SDK}_ARCH_${ARCH}_PATH}")

    # A directory where to put the xUnit-style XML test results.
    set(SWIFT_TEST_RESULTS_DIR
        "${CMAKE_BINARY_DIR}/${CMAKE_CFG_INTDIR}/swift-test-results/${VARIANT_TRIPLE}")

    set(command_clean_test_results_dir
        COMMAND "${CMAKE_COMMAND}" -E remove_directory "${SWIFT_TEST_RESULTS_DIR}"
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${SWIFT_TEST_RESULTS_DIR}")

    set(test_bin_dir "${CMAKE_CURRENT_BINARY_DIR}${VARIANT_SUFFIX}")
    set(validation_test_bin_dir
        "${CMAKE_CURRENT_BINARY_DIR}/../validation-test${VARIANT_SUFFIX}")

    swift_configure_lit_site_cfg(
        "${CMAKE_CURRENT_SOURCE_DIR}/lit.site.cfg.in"
        "${test_bin_dir}/lit.site.cfg"
        "test${VARIANT_SUFFIX}.lit.site.cfg")

    swift_configure_lit_site_cfg(
        "${CMAKE_CURRENT_SOURCE_DIR}/Unit/lit.site.cfg.in"
        "${test_bin_dir}/Unit/lit.site.cfg"
        "")

    swift_configure_lit_site_cfg(
        "${CMAKE_CURRENT_SOURCE_DIR}/../validation-test/lit.site.cfg.in"
        "${validation_test_bin_dir}/lit.site.cfg"
        "validation-test${VARIANT_SUFFIX}.lit.site.cfg")

    set(test_dependencies)
    get_test_dependencies("${SDK}" test_dependencies)
    list(APPEND test_dependencies
        "swift-test-stdlib-${SWIFT_SDK_${SDK}_LIB_SUBDIR}")

    if(SWIFT_BUILD_STDLIB AND SWIFT_INCLUDE_TESTS)
      list(APPEND test_dependencies
          "swift-reflection-test${VARIANT_SUFFIX}_signed")
    endif()

    if(NOT "${COVERAGE_DB}" STREQUAL "")
      list(APPEND test_dependencies "touch-covering-tests")
    endif()

    set(validation_test_dependencies
        "swiftStdlibCollectionUnittest-${SWIFT_SDK_${SDK}_LIB_SUBDIR}"
        "swiftStdlibUnicodeUnittest-${SWIFT_SDK_${SDK}_LIB_SUBDIR}")

    set(command_upload_stdlib)
    set(command_upload_swift_reflection_test)
    if("${SDK}" STREQUAL "IOS" OR "${SDK}" STREQUAL "TVOS" OR "${SDK}" STREQUAL "WATCHOS")
      # These are supported testing SDKs, but their implementation of
      # `command_upload_stdlib` is hidden.
    elseif("${SDK}" STREQUAL "ANDROID")
      if("${SWIFT_ANDROID_DEPLOY_DEVICE_PATH}" STREQUAL "")
        message(FATAL_ERROR
            "When running Android host tests, you must specify the directory on the device "
            "to which Swift build products will be deployed.")
      endif()

      # Warning: This step will fail if you do not have an Android device
      #          connected via USB. See docs/Android.md for details on
      #          how to run the test suite for Android.
      set(command_upload_stdlib
          COMMAND
              # Reboot the device and remove everything in its tmp
              # directory. Build products and test executables are pushed
              # to that directory when running the test suite.
              ${PYTHON_EXECUTABLE} "${SWIFT_SOURCE_DIR}/utils/android/adb_clean.py"
          COMMAND
              ${PYTHON_EXECUTABLE} "${SWIFT_SOURCE_DIR}/utils/android/adb_push_built_products.py"
              --ndk "${SWIFT_ANDROID_NDK_PATH}"
              --destination "${SWIFT_ANDROID_DEPLOY_DEVICE_PATH}"
              # Build products like libswiftCore.so.
              "${SWIFTLIB_DIR}/android"
              # These two directories may contain the same libraries,
              # but upload both to device just in case. Duplicates will be
              # overwritten, and uploading doesn't take very long anyway.
              "${SWIFT_ANDROID_${ARCH}_ICU_UC}"
              "${SWIFT_ANDROID_${ARCH}_ICU_I18N}")
    endif()
    add_custom_target("upload-stdlib${VARIANT_SUFFIX}"
        ${command_upload_stdlib}
        ${command_upload_swift_reflection_test}
        COMMENT "Uploading stdlib")

    foreach(test_mode ${TEST_MODES})
      set(LIT_ARGS "${SWIFT_TEST_EXTRA_ARGS} ${LLVM_LIT_ARGS}")
      separate_arguments(LIT_ARGS)

      if(NOT SWIFT_BUILD_STDLIB)
        list(APPEND LIT_ARGS
            "--param" "test_sdk_overlay_dir=${SWIFTLIB_DIR}/${SWIFT_SDK_${SDK}_LIB_SUBDIR}")
      endif()

      if(SWIFT_ENABLE_TENSORFLOW)
        list(APPEND LIT_ARGS
            "--param" "swift_tensorflow_path=${SWIFT_TENSORFLOW_TARGET_LIB_DIR}")
      endif()
      if(SWIFT_ENABLE_TENSORFLOW_GPU)
        list(APPEND LIT_ARGS
            "--param" "swift_tensorflow_gpu=true")
      endif()

      execute_process(COMMAND
          "${PYTHON_EXECUTABLE}" "-c" "import psutil"
          RESULT_VARIABLE python_psutil_status
          TIMEOUT 1 # second
          ERROR_QUIET)
      if(NOT python_psutil_status)
        list(APPEND LIT_ARGS "--timeout=3000") # 50 minutes
      endif()

      list(APPEND LIT_ARGS "--xunit-xml-output=${SWIFT_TEST_RESULTS_DIR}/lit-tests.xml")

      foreach(test_subset ${TEST_SUBSETS})
        set(directories)
        set(dependencies ${test_dependencies})

        if((test_subset STREQUAL "primary") OR
           (test_subset STREQUAL "validation") OR
           (test_subset STREQUAL "only_long") OR
           (test_subset STREQUAL "only_stress") OR
           (test_subset STREQUAL "all"))
          list(APPEND directories "${test_bin_dir}")
        endif()
        if((test_subset STREQUAL "validation") OR
           (test_subset STREQUAL "only_validation") OR
           (test_subset STREQUAL "only_long") OR
           (test_subset STREQUAL "only_stress") OR
           (test_subset STREQUAL "all"))
          list(APPEND directories "${validation_test_bin_dir}")
          list(APPEND dependencies ${validation_test_dependencies})
        endif()

        if("${SWIFT_SDK_${SDK}_OBJECT_FORMAT}" STREQUAL "ELF")
          list(APPEND dependencies swiftImageRegistration${VARIANT_SUFFIX})
        endif()

        set(test_subset_target_suffix "-${test_subset}")
        if(test_subset STREQUAL "primary")
          set(test_subset_target_suffix "")
        endif()

        set(test_mode_target_suffix "")
        if(NOT test_mode STREQUAL "optimize_none")
          set(test_mode_target_suffix "-${test_mode}")
        endif()

        set(test_target_name
            "check-swift${test_subset_target_suffix}${test_mode_target_suffix}${VARIANT_SUFFIX}")
        add_custom_target("${test_target_name}"
            ${command_upload_stdlib}
            ${command_upload_swift_reflection_test}
            ${command_clean_test_results_dir}
            COMMAND
              ${PYTHON_EXECUTABLE} "${LIT}"
              ${LIT_ARGS}
              "--param" "swift_test_subset=${test_subset}"
              "--param" "swift_test_mode=${test_mode}"
              ${directories}
            DEPENDS ${dependencies}
            COMMENT "Running ${test_subset} Swift tests for ${VARIANT_TRIPLE}"
            USES_TERMINAL)

        add_custom_target("${test_target_name}-custom"
            ${command_upload_stdlib}
            ${command_upload_swift_reflection_test}
            ${command_clean_test_results_dir}
            COMMAND
              ${PYTHON_EXECUTABLE} "${LIT}"
              ${LIT_ARGS}
              "--param" "swift_test_subset=${test_subset}"
              "--param" "swift_test_mode=${test_mode}"
            DEPENDS ${dependencies}
            COMMENT "Running ${test_subset} Swift tests for ${VARIANT_TRIPLE} from custom test locations"
            USES_TERMINAL)
        set_property(TARGET "${test_target_name}" "${test_target_name}-custom"
            PROPERTY FOLDER "Tests/check-swift")
      endforeach()
    endforeach()
  endforeach()
endforeach()

# Add shortcuts for the default variant.
foreach(test_mode ${TEST_MODES})
  foreach(test_subset ${TEST_SUBSETS})
    set(test_mode_target_suffix "")
    if(NOT test_mode STREQUAL "optimize_none")
      set(test_mode_target_suffix "-${test_mode}")
    endif()
    set(test_subset_target_suffix "-${test_subset}")
    if(test_subset STREQUAL "primary")
      set(test_subset_target_suffix "")
    endif()

    set(test_target_name
        "check-swift${test_subset_target_suffix}${test_mode_target_suffix}")
    add_custom_target("${test_target_name}"
        DEPENDS "${test_target_name}${SWIFT_PRIMARY_VARIANT_SUFFIX}")
    set_property(TARGET "${test_target_name}"
        PROPERTY FOLDER "Tests/check-swift")
  endforeach()
endforeach()
