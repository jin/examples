# Copyright 2016 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

HTTP_PROTOCOL = "http://"
MAVEN_CENTRAL_HOST = "repo1.maven.org"
MAVEN_CENTRAL_PATH = "/maven2"
MAVEN_CENTRAL_URL = HTTP_PROTOCOL + MAVEN_CENTRAL_HOST + MAVEN_CENTRAL_PATH

# TODO(jingwen): remove dependency from maven binary
MAVEN_DEP_PLUGIN="org.apache.maven.plugins:maven-dependency-plugin:2.8:get"

# Returns a string containing the contents of the BUILD file
def _create_build_file_contents(rule_name, jar_filename):
  return """
# DO NOT EDIT: automatically generated BUILD file for maven_jar rule {rule_name}

java_import(
    name = 'jar',
    jars = ['{jar_filename}'],
    visibility = ['//visibility:public']
)

filegroup(
    name = 'file',
    srcs = ['jar_filename'],
    visibility = ['//visibility:public']
)\n""".format(rule_name = rule_name, jar_filename = jar_filename)

def _validate_ctx_attr(ctx):
  if (ctx.attr.repository != "" and ctx.attr.server != ""):
    fail("%s specifies both 'repository' and 'server', " +
         "which are mutually exclusive options." % ctx.name)

# Creates a struct containing the different parts
# of an artifact's fully qualified name
def _create_artifact_struct(fully_qualified_name):
  parts = fully_qualified_name.split(":")
  if len(parts) != 3:
    fail("artifact must be defined as a fully qualified name. e.g. groupId:artifactId:version")

  group_id, artifact_id, version = parts
  return struct(
    fully_qualified_name = fully_qualified_name,
    group_id = group_id,
    artifact_id = artifact_id,
    version = version,
  )

# Creates a struct that contains all the paths
# needed to store the jar in bazel cache
def _create_path_struct(artifact):

  # e.g. guava-18.0.jar
  jar_filename = "%s-%s.jar" % (artifact.artifact_id, artifact.version)

  # e.g. com/google/guava/guava/18.0
  relative_folder = "/".join(artifact.group_id.split(".") +
                             [artifact.artifact_id] +
                             [artifact.version])

  # The symlink to the actual .jar is stored in this folder, along
  # with the BUILD file
  symlink_folder = "jar"

  return struct(
    jar_filename = jar_filename,
    sha1_filename = "%s.sha1" % jar_filename,
    sha256_filename = "%s.sha256" % jar_filename,
    relative_folder = relative_folder,
    symlink_folder = symlink_folder,

    # e.g. com/google/guava/guava/18.0/guava-18.0.jar
    relative_jar = "%s/%s" % (relative_folder, jar_filename),

    # e.g. jar/guava-18.0.jar
    symlink_jar = "%s/%s" % (symlink_folder, jar_filename),
  )


# This is the main implementation of the maven_jar rule.
# It does the following:
# 1) generate file paths
# 2) download the artifact with maven
# 3) create symlinks in the cache folder
def _maven_jar_impl(ctx):
  artifact = _create_artifact_struct(ctx.attr.artifact)
  paths = _create_path_struct(artifact)

  mkdir_status = ctx.execute(["mkdir", "-p", paths.relative_folder, paths.symlink_folder])
  if mkdir_status.return_code != 0:
    fail("Failed to create destination folder for %s" % artifact.fully_qualified_name)

  command = [
    "bash", "-c", """
      set -ex
      mvn {flags} {dep_get_plugin} \
      "-DrepoUrl={repository}" \
      "-Dartifact={artifact}" \
      "-Dtransitive={transitive}" \
      "-Ddest={dest}" \
    """.format(
    flags = "-e -X",
    dep_get_plugin = MAVEN_DEP_PLUGIN,
    repository = ctx.attr.repository,
    artifact = artifact.fully_qualified_name,
    transitive = str(ctx.attr.transitive).lower(),
    dest = ctx.path(paths.relative_jar),
    )
  ]

  build_file_contents = _create_build_file_contents(ctx.name, paths.jar_filename)
  ctx.file('%s/BUILD' % paths.symlink_folder, build_file_contents, False)

  exec_result = ctx.execute(command)
  if exec_result.return_code != 0:
    fail("error downloading %s:\n%s" % (ctx.name, exec_result.stderr))

  ctx.symlink(paths.relative_jar, paths.symlink_jar)

  # print(exec_result.stdout)

# TODO(jingwen)
# def _maven_server_impl(repo_ctx):
#   print('TODO')

_maven_jar_attrs = {
  "artifact": attr.string(default="", mandatory=True),
  "repository": attr.string(default=MAVEN_CENTRAL_HOST),
  "server": attr.string(default=""),
  "sha1": attr.string(default=""),
  "sha256": attr.string(default=""),
  "transitive": attr.bool(default=True),
}

# TODO(jingwen): figure out maven settings concatenation
# _maven_server_attrs = {
#     "settings_file": attr.string(default=""),
#     "url": attr.string(default=MAVEN_CENTRAL_URL),
# }

maven_jar = repository_rule(
  _maven_jar_impl,
  attrs=_maven_jar_attrs,
  local=False,
)

# maven_server = repository_rule(
#     _maven_server_impl,
#     attrs=_maven_server_attrs,
#     local=True,
# )
