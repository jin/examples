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

def _construct_url(protocol, host, path):
  return protocol + host + path

HTTP_PROTOCOL = "http://"
MAVEN_CENTRAL_HOST = "repo1.maven.org"
MAVEN_CENTRAL_PATH = "/maven2"
MAVEN_CENTRAL_URL = _construct_url(HTTP_PROTOCOL, MAVEN_CENTRAL_HOST, MAVEN_CENTRAL_PATH)

MAVEN_GLOBAL_SETTINGS_PATH = "$M2_HOME/conf/settings.xml"
MAVEN_USER_SETTINGS_PATH = "$HOME/.m2/settings.xml"

MAVEN_DEP_PLUGIN="org.apache.maven.plugins:maven-dependency-plugin:2.8:get"

def _create_build_file(ctx):
  artifact = _deconstruct_artifact_name(ctx.attr.artifact)
  return """
# DO NOT EDIT: automatically generated BUILD file for maven_jar rule {name}

java_import(
    name = 'jar',
    jars = ['{artifact_id}-{version}.jar'],
    visibility = ['//visibility:public']
)

filegroup(
    name = 'file',
    srcs = ['{artifact_id}-{version}.jar'],
    visibility = ['//visibility:public']
)
    """.format(
      name = ctx.name,
      artifact_id = artifact.artifact_id,
      version = artifact.version,
    )

def _check_server_and_repo(ctx):
  if (ctx.attr.repository != "" and ctx.attr.server != ""):
    fail("%s specifies both 'repository' and 'server', " +
         "which are mutually exclusive options." % ctx.name)

def _deconstruct_artifact_name(artifact):
  parts = artifact.split(":")
  if len(parts) != 3:
    fail("artifact must be defined as a fully qualified name. e.g. groupId:artifactId:version")
  group_id, artifact_id, version = parts
  return struct(
    fully_qualified_name = artifact,
    group_id = group_id,
    artifact_id = artifact_id,
    version = version,
  )

def _maven_jar_impl(ctx):
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
            artifact = ctx.attr.artifact,
            transitive = str(ctx.attr.transitive).lower(),
            dest = ctx.path("./jar"),
          )
      ]
  print("".join(command))
  print(_create_build_file(ctx))

  # exec_result = ctx.execute(command)
  # if exec_result.return_code != 0:
  #   fail("error downloading %s:\n%s" % (ctx.name, exec_result.stderr))
  # else:
  #   print(exec_result.stdout)

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
