load("@gmaven_rules//:defs.bzl", "gmaven_artifact")

android_library(
    name = "greeter_test_lib",
    srcs = ["GreeterTest.java"],
    custom_package = "com.example.bazel.test",
    visibility = ["//src/test:__subpackages__"],
    deps = [
        ":test_deps",
        "//src/main/java/com/example/bazel:greeter_activity",
    ],
)

androidxLibVersion = "1.0.0"

coreVersion = "1.1.0-beta01"

extJUnitVersion = "1.1.0-beta01"

extTruthVersion = "1.1.0-beta01"

runnerVersion = "1.1.1-beta01"

rulesVersion = "1.1.1-beta01"

espressoVersion = "3.1.1-beta01"

uiAutomatorVersion = "2.2.0"

minSdkVersion = "14"

targetSdkVersion = "28"

android_library(
    name = "test_deps",
    exports = [
        gmaven_artifact("androidx.annotation:annotation:jar:" + androidxLibVersion),
        gmaven_artifact("androidx.test.espresso:espresso-core:aar:" + espressoVersion),
        gmaven_artifact("androidx.test:rules:aar:" + rulesVersion),
        gmaven_artifact("androidx.test:runner:aar:" + runnerVersion),
        gmaven_artifact("androidx.test:monitor:aar:" + runnerVersion),
        gmaven_artifact("androidx.test.ext:junit:aar:" + extJUnitVersion),
        gmaven_artifact("androidx.test:core:aar:" + coreVersion),
        #        "@com_google_guava_guava//jar",
        "@com_google_inject_guice//jar",
        "@javax_inject_javax_inject//jar",
        "@junit_junit//jar",
        "@org_hamcrest_java_hamcrest//jar",
    ],
)
