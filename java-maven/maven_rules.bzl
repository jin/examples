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
"""Rules for retrieving Maven dependencies"""

MAVEN_CENTRAL_URL = "https://repo1.maven.org/maven2/"

# The maven plugin used to retrieve artifacts. Comes with useful flags
# such as transitive deps, download destination and remote repositories.
# MAVEN_DEP_PLUGIN = "org.apache.maven.plugins:maven-dependency-plugin:2.8:get"
MAVEN_DEP_PLUGIN = "org.apache.maven.plugins:maven-dependency-plugin:2.8:get"

# Binary dependencies needed for running the bash commands
DEPS = ["mvn", "xmlstarlet", "sha1sum"]

DEFAULT_REPO = "DEFAULT_REPO"

def _set_env_var(ctx, key, value):
  ctx.os.environ.update({ key: value })

def _get_env_var(ctx, key):
  ctx.os.environ.get(key)

#############
# maven_jar #
#############

def _check_dependencies(ctx):
  for dep in DEPS:
    if ctx.which(dep) == None:
      fail("%s: maven_jar requires %s as a dependency. Please check your PATH."
           % (ctx.name, dep))


def _validate_ctx(ctx):
  if (ctx.attr.repository != "" and ctx.attr.server != None):
    fail(("%s specifies both 'repository' and 'server', " +
          "which are mutually exclusive options. " +
          "Please specify at most one of them.\n") % ctx.name)


def _create_path_struct(ctx, artifact):
  """Creates a struct that contains all the paths needed to store the jar in bazel cache"""
  # e.g. guava-18.0.jar
  jar_filename = "%s-%s.jar" % (artifact.artifact_id, artifact.version)
  sha1_filename = "%s.sha1" % jar_filename

  # e.g. com/google/guava/guava/18.0
  jar_dir = "/".join(artifact.group_id.split(".") +
                         [artifact.artifact_id] +
                         [artifact.version])

  # The symlink to the actual .jar is stored in this dir, along
  # with the BUILD file.
  symlink_dir = "jar"

  return struct(
      jar_filename = jar_filename,
      sha1_filename = sha1_filename,

      # Compute the exec_root absolute path for the dirs
      jar_dir = ctx.path(jar_dir),
      symlink_dir = ctx.path(symlink_dir),

      # e.g. {exec_root}/external/com_google_guava_guava/ \
      #        com/google/guava/guava/18.0/guava-18.0.jar
      absolute_jar_path = ctx.path("%s/%s" % (jar_dir, jar_filename)),
      absolute_sha1_path = ctx.path("%s/%s" % (jar_dir, sha1_filename)),

      # e.g. {exec_root}/external/com_google_guava_guava/jar/guava-18.0.jar
      symlink_jar_path = ctx.path("%s/%s" % (symlink_dir, jar_filename)),

      working_dir = ctx.path("./"),
      maven_settings_path = ctx.path("./settings.xml"),
      local_maven_repo_dir = ctx.path("./m2/repository/"),
  )


def _create_dirs(ctx, paths):
  mkdir_status = ctx.execute([
      "bash", "-c",
      "set -ex",
      "(mkdir -p %s %s %s)" % (paths.jar_dir, paths.symlink_dir, paths.local_maven_repo_dir)
  ])
  if mkdir_status.return_code != 0:
    fail("%s: Failed to create dirs in execution root.\n" % ctx.name)


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
    srcs = ['{jar_filename}'],
    visibility = ['//visibility:public']
)\n""".format(rule_name = rule_name, jar_filename = jar_filename)


def _generate_build_file(ctx, paths):
  build_file_contents = _create_build_file_contents(ctx.name, paths.jar_filename)
  ctx.file('%s/BUILD' % paths.symlink_dir, build_file_contents, False)


# Creates a struct containing the different parts
# of an artifact's fully qualified name
def _create_artifact_struct(ctx):
  fully_qualified_name = ctx.attr.artifact
  parts = fully_qualified_name.split(":")

  if len(parts) != 3:
    fail(("%s: Artifact \"%s\" must be defined as a fully " +
         "qualified name. e.g. groupId:artifactId:version.\n")
         % (ctx.name, fully_qualified_name))

  group_id, artifact_id, version = parts
  return struct(
      fully_qualified_name = fully_qualified_name,
      group_id = group_id,
      artifact_id = artifact_id,
      version = version,
  )


# Maven's dependency:get plugin doesn't replace the repository url with CLI options,
# even with the -DrepoUrl or -DremoteRepositories flags.
#
# Instead, it reads directly Maven's settings.xml list of mirrors, and finds the one
# that is the mirror of the 'central' repository.
#
# This function creates the mirror element as specified either by the default
# MAVEN_CENTRAL_URL, maven_jar's repository attribute or maven_server's url attribute.
def _create_empty_maven_settings(ctx, path):
  settings_content = """
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0
    https://maven.apache.org/xsd/settings-1.0.0.xsd">
  <localRepository/>
  <interactiveMode/>
  <usePluginRegistry/>
  <offline/>
  <pluginGroups/>
  <servers/>
  <mirrors/>
  <proxies/>
  <profiles/>
  <activeProfiles/>
</settings>"""
  ctx.file(path, settings_content, False)

def _create_repository_setting(ctx, repository, path):
  _create_empty_maven_settings(ctx, path)

  mirror_dict = {
      "id": "bazel-mirror",
      "url": repository,
      "mirrorOf": "central"
  }
  mirror_setting = ""

  for key in mirror_dict.keys():
    mirror_setting = mirror_setting + \
      "| xmlstarlet ed --subnode /_:settings/_:mirrors/_:mirror " + \
      "--type elem -n %s -v \"%s\" " % (key, mirror_dict.get(key))

  command = ["bash", "-c", """
set -ex
  (xmlstarlet ed --subnode /_:settings/_:mirrors \
  --type elem -n 'mirror' -v \"\" {settings_file} \
  {mirror_setting})
""".format(
     settings_file = path,
     mirror_setting = mirror_setting,
   )]

  exec_result = ctx.execute(command)
  if exec_result.return_code != 0:
    fail("xmlstarlet fail\n%s" % exec_result.stderr)
  else:
    print(exec_result.stdout)
    ctx.file(path, exec_result.stdout, False)


def _file_exists(ctx, path):
  exec_result = ctx.execute(["bash", "-c", "[ -e %s ] && exit 0 || exit 1" % path])
  return exec_result.return_code == 0

def _download_artifact(ctx, fully_qualified_name, paths):
  repository = ctx.attr.repository
  if repository == "":
    if _get_env_var(ctx, DEFAULT_REPO) == None:
      _set_env_var(ctx, DEFAULT_REPO, MAVEN_CENTRAL_URL)
    repository = _get_env_var(ctx, DEFAULT_REPO)

  _create_repository_setting(ctx, repository, paths.maven_settings_path)

  command = [
    "bash", "-c", """
set -ex
mvn {flags} {dep_get_plugin} \
"-Dmaven.repo.local={local_maven_repo_dir}" \
"-Dartifact={fully_qualified_name}" \
"-Ddest={dest}" \
    """.format(
      flags = ("-e -X --settings %s" % paths.maven_settings_path),
      dep_get_plugin = MAVEN_DEP_PLUGIN,
      local_maven_repo_dir = paths.local_maven_repo_dir,
      fully_qualified_name = fully_qualified_name,
      dest = paths.absolute_jar_path,
    )
  ]
  exec_result = ctx.execute(command)
  if exec_result.return_code != 0:
    print(exec_result.stdout)
    fail(("%s: Error downloading %s. Please check that your artifact ID " +
          "or repository is correct.\n%s") %
          (ctx.name, fully_qualified_name, exec_result.stderr))


def _compute_shasum(ctx, jar_path):
  command = ["bash", "-c", """
set -ex
sha1sum %s | awk '{printf $1}'
  """ % jar_path]
  shasum_status = ctx.execute(command)
  if shasum_status.return_code != 0:
    fail("%s: Error obtaining sha1 of %s: %s\n"
         % (ctx.name, jar_path, shasum_status.stderr))
  return shasum_status.stdout


def _verify_checksum(ctx, paths, sha1 = ""):
  if sha1 == "":
    return
  if len(sha1) != 40:
    fail("%s: %s has an invalid length for a sha1sum (should be 40)" % (ctx.name, sha1))

  actual_sha1 = _compute_shasum(ctx, paths.absolute_jar_path)
  if sha1.lower() != actual_sha1.lower():
    fail(("[rule_name} has SHA-1 of {actual_sha1}, " +
            "does not match expected SHA-1 {expected_sha1}").format(
              rule_name = ctx.name,
              expected_sha1 = sha1,
              actual_sha1 = actual_sha1))
  else:
    ctx.file(paths.absolute_sha1_path, sha1, False)


# This is the main implementation of the maven_jar rule.
# It does the following:
# 1) generate file paths
# 2) download the artifact with maven
# 3) create symlinks in the cache dir
def _maven_jar_impl(ctx):
  _check_dependencies(ctx)
  _validate_ctx(ctx)

  artifact = _create_artifact_struct(ctx)
  paths = _create_path_struct(ctx, artifact)

  _create_dirs(
      ctx = ctx,
      paths = paths,
  )

  _generate_build_file(
      ctx = ctx,
      paths = paths,
  )

  _download_artifact(
      ctx = ctx,
      fully_qualified_name = artifact.fully_qualified_name,
      paths = paths,
  )

  _verify_checksum(
      ctx = ctx,
      paths = paths,
      sha1 = ctx.attr.sha1,
  )
  ctx.symlink(paths.absolute_jar_path, paths.symlink_jar_path)


_maven_jar_attrs = {
    "artifact": attr.string(default="", mandatory=True),
    "repository": attr.string(),
    "server": attr.label(default=None),
    "sha1": attr.string(default=""),
    "_url": attr.string()
}


_maven_jar = repository_rule(
    _maven_jar_impl,
    attrs=_maven_jar_attrs,
    local=False,
)


# Macro to handle maven_server edgecase
def maven_jar(name, server = None, repository = "", **kwargs):
  server_url = repository
  if server:
    existing_server_rule = native.existing_rule(server)
    if existing_server_rule:
      server_url = existing_server_rule["url"]
    else:
      fail(("%s: Could not find maven repository %s. Please ensure " +
            "that the maven_server rule is declared before this " +
            "maven_jar rule. This is a known limit with the experimental " +
            "Skylark maven rules.") % (name, server))

  _maven_jar(name = name, repository = server_url, **kwargs)


################
# maven_server #
################

def _maven_server_impl(ctx):
  if ctx.attrs.settings_file != "":
    fail(("%s: The experimental maven_jar rule does not read from a " +
          "custom maven settings_file.") % ctx.name)
  # Fallback to the native implementation
  if ctx.name == "default" and ctx.attrs.url != "":
    _set_env_var(ctx, DEFAULT_REPO, ctx.attrs.url)
  native.maven_server(name = ctx.name, url = ctx.attrs.url)


_maven_server_attrs = {
    "settings_file": attr.string(default=""),
    "url": attr.string(default=""),
}


maven_server = repository_rule(
    _maven_server_impl,
    attrs=_maven_server_attrs,
    local=False,
)
